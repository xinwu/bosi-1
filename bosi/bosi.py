import argparse
import datetime
import lib.constants as const
import os
import Queue
import random
import subprocess32 as subprocess
import threading
import time
import yaml

from collections import OrderedDict
from lib.environment import Environment
from lib.helper import Helper
from lib.util import safe_print

# queue to store all controller nodes
controller_node_q = Queue.Queue()

# queue to store all nodes
node_q = Queue.Queue()
# copy the node_q to this when original list is created
certify_node_q = Queue.Queue()
verify_node_q = Queue.Queue()
support_node_q = Queue.Queue()
# keep track of verified nodes
node_pass = {}
node_fail = {}

# result dict
node_dict = {}
time_dict = {}


def worker_setup_node(q):
    while True:
        node = q.get()
        # copy ivs pkg to node
        Helper.copy_pkg_scripts_to_remote(node)

        # deploy node
        safe_print("Start to deploy %(fqdn)s\n" %
                   {'fqdn': node.fqdn})
        if node.cleanup and node.role == const.ROLE_NEUTRON_SERVER:
            Helper.run_command_on_remote(node,
                (r'''sudo bash %(dst_dir)s/%(hostname)s_ospurge.sh''' %
                {'dst_dir': node.dst_dir,
                 'hostname': node.hostname,
                 'log': node.log}))

        # a random delay to smooth apt-get/yum
        delay = random.random() * 10.0
        time.sleep(delay)

        start_time = datetime.datetime.now()
        Helper.run_command_on_remote(node,
            (r'''sudo bash %(dst_dir)s/%(hostname)s.sh''' %
            {'dst_dir': node.dst_dir,
             'hostname': node.hostname,
             'log': node.log}))
        end_time = datetime.datetime.now()

        # parse setup log
        diff = Helper.timedelta_total_seconds(end_time - start_time)
        node.set_time_diff(diff)
        node = Helper.update_last_log(node)
        node_dict[node.fqdn] = node
        time_dict[node.fqdn] = diff

        # when deploying T5 on UBUNTU, reboot compute nodes
        Helper.reboot_if_necessary(node)

        safe_print("Finish deploying %(fqdn)s, cost time: %(diff).2f\n" %
                   {'fqdn': node.fqdn, 'diff': node.time_diff})
        q.task_done()


def certify_node_setup(q):
    while True:
        node = q.get()
        if node.certificate_dir:
            if not os.path.isfile("%s/ca.cert" % node.certificate_dir):
                safe_print("Missing ca.cert in %s\n" % node.certificate_dir)
                break
        Helper.certify_node(node)
        q.task_done()


def support_node_setup(q):
    while True:
        node = q.get()
        Helper.support_node(node)
        q.task_done()


def verify_node_setup(q):
    while True:
        node = q.get()
        all_service_status = 'Service status for node: ' + node.fqdn
        # check services are running and IVS version is correct
        if node.deploy_dhcp_agent:
            dhcp_status = Helper.check_os_service_status(
                node, "neutron-dhcp-agent")
            all_service_status = (all_service_status +
                                  ' | DHCP Agent ' + dhcp_status)
            metadata_status = Helper.check_os_service_status(
                node, "neutron-metadata-agent")
            all_service_status = (all_service_status +
                                  ' | Metadata Agent ' + metadata_status)
        if node.deploy_l3_agent and node.deploy_mode == const.T5:
            l3_status = Helper.check_os_service_status(
                node, "neutron-l3-agent")
            all_service_status = (all_service_status +
                                  ' | L3 Agent ' + l3_status)
        # for T5 deployment, check LLDP service status on compute nodes
        if node.deploy_mode == const.T5 and node.role != const.ROLE_NEUTRON_SERVER:
            lldp_status = Helper.check_os_service_status(node, "send_lldp")
            all_service_status = (all_service_status +
                                  ' | LLDP Service ' + lldp_status)
        # for T6 deployment, check IVS status and version too
        if node.deploy_mode == const.T6:
            # check ivs status and version
            ivs_status = Helper.check_os_service_status(node, "ivs")
            if ivs_status == ':-)':
                # ivs is OK. check version
                ivs_version = Helper.check_ivs_version(node)
                all_service_status = (all_service_status +
                                      ' | IVS version ' + ivs_version)
            else:
                # ivs not OK
                all_service_status = (all_service_status +
                                      ' | IVS ' + ivs_status)
            # check neutron-bsn-agent status
            bsn_agent_status = Helper.check_os_service_status(
                node, "neutron-bsn-agent")
            all_service_status = (all_service_status +
                                  ' | BSN Agent ' + bsn_agent_status)
        # after forming the complete string, put in respective list
        if ":-(" not in all_service_status:
            node_pass[node.fqdn] = all_service_status
        else:
            node_fail[node.fqdn] = all_service_status
        q.task_done()


def deploy_bcf(config, mode, fuel_cluster_id, rhosp, tag, cleanup,
               verify, verify_only, skip_ivs_version_check,
               certificate_dir, certificate_only, generate_csr,
               support):
    # Deploy setup node
    safe_print("Start to prepare setup node\n")
    env = Environment(config, mode, fuel_cluster_id, rhosp, tag, cleanup,
                      skip_ivs_version_check, certificate_dir)
    Helper.common_setup_node_preparation(env)
    controller_nodes = []

    # Generate detailed node information
    safe_print("Start to setup Big Cloud Fabric\n")
    nodes_yaml_config = config['nodes'] if 'nodes' in config else None
    node_dic = Helper.load_nodes(nodes_yaml_config, env)

    if generate_csr:
        safe_print("Start to generate csr for virtual switches.\n")
        # create ~/csr and ~/key directory
        Helper.run_command_on_local("mkdir -p %s" % const.CSR_DIR)
        Helper.run_command_on_local("mkdir -p %s" % const.KEY_DIR)
        for hostname, node in node_dic.iteritems():
            if node.skip:
                safe_print("skip node %(fqdn)s due to %(error)s\n" %
                           {'fqdn': node.fqdn, 'error': node.error})
                continue

            if node.tag != node.env_tag:
                safe_print("skip node %(fqdn)s due to mismatched tag\n" %
                           {'fqdn': node.fqdn})
                continue
            if node.deploy_mode == const.T6 and node.role == const.ROLE_COMPUTE:
                Helper.generate_csr(node)
        safe_print("Finish generating csr for virtual switches.\n")
        return

    # copy neutron config from neutron server to setup node
    for hostname, node in node_dic.iteritems():
        if node.role == const.ROLE_NEUTRON_SERVER:
            controller_nodes.append(node)
    Helper.copy_neutron_config_from_controllers(controller_nodes)
    if env.openstack_release == const.OS_RELEASE_JUNO:
        Helper.copy_dhcp_scheduler_from_controllers(controller_nodes)

    # check if vlan is the tenant network type for fuel environment
    if not Helper.check_if_vlan_is_used(controller_nodes):
        safe_print("tenant network type is not vlan. Stop deploying.\n")
        return

    # prepare keystone client from /etc/neutron/api-paste.ini
    if env.openstack_release != const.OS_RELEASE_JUNO:
        Helper.prepare_keystone_client(controller_nodes)

    # Generate scripts for each node
    for hostname, node in node_dic.iteritems():
        if support:
            support_node_q.put(node)

        if node.skip:
            safe_print("skip node %(fqdn)s due to %(error)s\n" %
                       {'fqdn': node.fqdn, 'error': node.error})
            continue

        if node.tag != node.env_tag:
            safe_print("skip node %(fqdn)s due to mismatched tag\n" %
                       {'fqdn': node.fqdn})
            continue

        if node.os == const.CENTOS:
            Helper.generate_scripts_for_centos(node)
        elif node.os == const.UBUNTU:
            Helper.generate_scripts_for_ubuntu(node)
        elif node.os == const.REDHAT:
            Helper.generate_scripts_for_redhat(node)

        if node.role == const.ROLE_NEUTRON_SERVER:
            controller_node_q.put(node)
        else:
            # python doesn't have deep copy for Queue, hence add to all
            node_q.put(node)
            verify_node_q.put(node)
            if node.deploy_mode == const.T6 and node.role == const.ROLE_COMPUTE:
                certify_node_q.put(node)

        if node.rhosp:
            Helper.chmod_node(node)

    with open(const.LOG_FILE, "a") as log_file:
        version = Helper.run_command_on_local("pip show bosi")
        log_file.write(str(version))
        for hostname, node in node_dic.iteritems():
            log_file.write(str(node))

    if support:
        safe_print("Start to collect logs.\n")
        # copy installer logs to ~/support
        Helper.run_command_on_local("mkdir -p %s" % const.SUPPORT_DIR)
        Helper.run_command_on_local("cp -r %(src)s %(dst)s" %
                                   {"src": const.LOG_FILE,
                                    "dst": const.SUPPORT_DIR})
        Helper.run_command_on_local("cp -r %(setup_node_dir)s/%(generated_script_dir)s %(dst)s" %
                                   {"setup_node_dir": env.setup_node_dir,
                                    "generated_script_dir": const.GENERATED_SCRIPT_DIR,
                                    "dst": const.SUPPORT_DIR})

        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=support_node_setup,
                                 args=(support_node_q,))
            t.daemon = True
            t.start()
        support_node_q.join()
        # compress ~/support
        Helper.run_command_on_local("cd /tmp; tar -czf support.tar.gz support")
        safe_print("Finish collecting logs. logs are at /tmp/support.tar.gz.\n")
        return

    # in case of verify_only or certificate_only, do not deploy
    if (not verify_only) and (not certificate_only):
        # Use single thread to setup controller nodes
        t = threading.Thread(target=worker_setup_node,
                             args=(controller_node_q,))
        t.daemon = True
        t.start()
        controller_node_q.join()

        # Use multiple threads to setup compute nodes
        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=worker_setup_node, args=(node_q,))
            t.daemon = True
            t.start()
        node_q.join()

        sorted_time_dict = OrderedDict(sorted(time_dict.items(),
                                              key=lambda x: x[1]))
        for fqdn, h_time in sorted_time_dict.items():
            safe_print("node: %(fqdn)s, time: %(time).2f, "
                       "last_log: %(log)s\n" %
                       {'fqdn': fqdn, 'time': h_time,
                        'log': node_dict[fqdn].last_log})

        safe_print("Big Cloud Fabric deployment finished! "
                   "Check %(log)s on each node for details.\n" %
                   {'log': const.LOG_FILE})

    if certificate_dir or certificate_only:
        # certify each node
        safe_print("Start to certify virtual switches.\n")
        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=certify_node_setup,
                                 args=(certify_node_q,))
            t.daemon = True
            t.start()
        certify_node_q.join()
        safe_print('Certifying virtual switches done.\n')

    if verify or verify_only:
        # verify each node and post results
        safe_print("Verifying deployment for all compute nodes.\n")
        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=verify_node_setup,
                                 args=(verify_node_q,))
            t.daemon = True
            t.start()
        verify_node_q.join()
        # print status
        # success nodes
        safe_print('Deployed successfully to: \n')
        for node_element in node_pass:
            safe_print(node_element + '\n')
        # failed nodes
        safe_print('Deployment to following failed: \n')
        for node_element in node_fail:
            safe_print(str(node_element) + ' : '
                       + str(node_fail[node_element]) + '\n')


def main():
    # Parse configuration
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--config-file", required=True,
                        help="BCF YAML configuration file")
    parser.add_argument("-m", "--deploy-mode", required=False,
                        choices=['pfabric', 'pvfabric']),
    parser.add_argument('-f', "--fuel-cluster-id", required=False,
                        help=("Fuel cluster ID. Fuel settings may override "
                              "YAML configuration. "
                              "Please refer to config.yaml"))
    parser.add_argument('-r', "--rhosp", action='store_true', default=False,
                        help="red hat openstack director is the installer.")
    parser.add_argument('-t', "--tag", required=False,
                        help="Deploy to tagged nodes only.")
    parser.add_argument('--cleanup', action='store_true', default=False,
                        help="Clean up existing routers, "
                             "networks and projects.")
    parser.add_argument('--skip-ivs-version-check', action='store_true',
                        default=False, help="Skip ivs version check.")
    parser.add_argument('--verify', action='store_true', default=False,
                        help="Verify service status for compute nodes "
                             "after deployment.")
    parser.add_argument('--verifyonly', action='store_true', default=False,
                        help=("Verify service status for compute nodes "
                              "after deployment. Does not deploy BCF "
                              "specific changes."))
    parser.add_argument('--certificate-dir', required=False,
                        help=("The directory that has the certificates for "
                              "virtual switches. This option requires certificates "
                              "to be ready in the directory. This option will deploy "
                              "certificate to the corresponding node based on the mac "
                              "address. Virtual switch will talk TLS afterward."))
    parser.add_argument('--certificate-only', action='store_true', default=False,
                        help=("By turning on this flag, bosi will only deploy certificate "
                              "to each node. It requires --certificate-dir to be specified."))
    parser.add_argument('--generate-csr', action='store_true', default=False,
                        help=("By turning on this flag, bosi will generate csr on behalf of "
                              "virtual switches. User needs to certify these csr and use "
                              "--certificate-dir to specify the certificate directory."))
    parser.add_argument('--support', action='store_true', default=False,
                        help=("Collect openstack logs."))

    args = parser.parse_args()
    if args.fuel_cluster_id and args.rhosp:
        safe_print("Cannot have both fuel and rhosp as openstack installer.\n")
        return
    if args.certificate_only and (not args.certificate_dir):
        safe_print("--certificate-only requires the existence of --certificate-dir.\n")
        return

    # Check if network is working properly
    code = subprocess.call("wget www.bigswitch.com --timeout=5", shell=True)
    if code != 0:
        safe_print("Network is not working properly, quit deployment\n")
        exit(1)
    subprocess.call("rm -f index.html*", shell=True)

    with open(args.config_file, 'r') as config_file:
        config = yaml.load(config_file)
    deploy_bcf(config, args.deploy_mode, args.fuel_cluster_id, args.rhosp,
               args.tag, args.cleanup,
               args.verify, args.verifyonly,
               args.skip_ivs_version_check,
               args.certificate_dir, args.certificate_only,
               args.generate_csr, args.support)


if __name__ == '__main__':
    main()
