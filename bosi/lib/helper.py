import constants as const
import json
import netaddr
import os
import socket
import string
import subprocess32 as subprocess
import yaml

from bridge import Bridge
from membership_rule import MembershipRule
from node import Node
from rest import RestLib
from util import safe_print

class Helper(object):

    @staticmethod
    def get_uname(node, node_config):
        # get uname
        output = Helper.run_command_on_remote(node, "uname -n")
        if 'Error' not in output:
            uname = output.strip()
            if len(uname) > const.UNAME_CUTOFF:
                safe_print("hostname %(hostname)s is longer than %(cutoff)d"
                           " characters, skip\n" %
                           {'hostname': node_config['hostname'],
                            'cutoff': const.UNAME_CUTOFF})
                return None
            return uname
        else:
            safe_print("Error getting node %(hostname)s uname:\n%(error)s\n"
                       % {'hostname': node_config['hostname'],
                          'error': output})
            return None

    @staticmethod
    def reboot_if_necessary(node):
        if node.deploy_mode != const.T5:
            return
        if node.os != const.UBUNTU:
            return
        if node.role != const.ROLE_COMPUTE:
            return
        output, error = Helper.run_command_on_remote_without_timeout(node,
            "sudo cat /proc/net/bonding/%s | grep xor | wc -l" % node.bond)
        if output and (output.strip() == '1'):
            return
        Helper.run_command_on_remote(node, r'''sudo reboot''')
        safe_print("Node %(hostname)s rebooted. Wait for it to "
                   "come back up.\n" %
                   {'hostname': node.hostname})

    @staticmethod
    def timedelta_total_seconds(timedelta):
        return ((timedelta.microseconds + 0.0 +
                (timedelta.seconds + timedelta.days * 24 * 3600)
                * 10 ** 6) / 10 ** 6)

    @staticmethod
    def chmod_node(node):
        Helper.run_command_on_remote_without_timeout(
            node, "sudo chmod -R 777 %s" % node.dst_dir)
        Helper.run_command_on_remote_without_timeout(
            node, "sudo touch %s" % node.log)
        Helper.run_command_on_remote_without_timeout(
            node, "sudo chmod -R 777 %s" % node.log)

    @staticmethod
    def get_setup_node_ip():
        """
        Get the setup node's eth0 ip
        """
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('bigswitch.com', 0))
        return s.getsockname()[0]

    @staticmethod
    def run_command_on_local_without_timeout(command):
        output, error = subprocess.Popen(
            command, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, shell=True).communicate()
        return output, error

    @staticmethod
    def run_command_on_remote_with_key_without_timeout(
        node_ip, node_user, command):
        """
        Run cmd on remote node.
        """
        local_cmd = (r'''ssh -t -oStrictHostKeyChecking=no -o '''
                     '''LogLevel=quiet %(user)s'''
                     '''@%(hostname)s "%(remote_cmd)s"''' %
                     {'hostname': node_ip,
                     'remote_cmd': command,
                     'user': node_user})
        return Helper.run_command_on_local_without_timeout(local_cmd)

    @staticmethod
    def run_command_on_local(command, user_timeout=600):
        """
        Use subprocess32's check_output to run command with timeout
        """
        try:
            output = subprocess.check_output(
                command, stderr=subprocess.STDOUT,
                timeout=user_timeout, shell=True)
            return output
        except Exception as e:
            msg = "Error executing command %s: %s\n" % (command, e)
            safe_print(msg)
            return msg

    @staticmethod
    def run_command_on_remote_with_passwd(node, command, timeout=600):
        """
        Run cmd on remote node.
        """
        local_cmd = (r'''sshpass -p %(pwd)s ssh -t '''
                     '''-oStrictHostKeyChecking=no -o LogLevel=quiet '''
                     '''%(user)s@%(hostname)s "echo %(pwd)s | '''
                     '''sudo -S %(remote_cmd)s | tee %(log)s 2>&1"''' %
                     {'user': node.user, 'hostname': node.hostname,
                      'pwd': node.passwd, 'log': node.log,
                      'remote_cmd': command})
        return Helper.run_command_on_local(local_cmd, timeout)

    @staticmethod
    def run_command_on_remote_with_passwd_without_timeout(
        hostname, user, passwd, command):
        local_cmd = (r'''sshpass -p %(pwd)s ssh -t '''
                     '''-oStrictHostKeyChecking=no '''
                     '''-o LogLevel=quiet %(user)s@%(hostname)s "'''
                     '''echo %(pwd)s | sudo -S %(remote_cmd)s"''' %
                     {'user': user, 'hostname': hostname,
                      'pwd': passwd, 'log': const.LOG_FILE,
                      'remote_cmd': command})
        return Helper.run_command_on_local_without_timeout(local_cmd)

    @staticmethod
    def copy_dir_to_remote_with_passwd(node, src_dir, dst_dir):
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_remote_with_passwd(node, mkdir_cmd)
        scp_cmd = (r'''sshpass -p %(pwd)s scp -oStrictHostKeyChecking=no '''
                   '''-o LogLevel=quiet -r %(src_dir)s  '''
                   '''%(user)s@%(hostname)s:%(dst_dir)s/ >> %(log)s 2>&1''' %
                   {'user': node.user, 'hostname': node.hostname,
                    'pwd': node.passwd, 'log': node.log,
                   'src_dir': src_dir, 'dst_dir': dst_dir})
        Helper.run_command_on_local(scp_cmd)

    @staticmethod
    def copy_file_to_remote_with_passwd(
        node, src_file, dst_dir, dst_file, mode=777):
        """
        Copy file from local node to remote node,
        create directory if remote directory doesn't exist,
        change the file mode as well.
        """
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_remote_with_passwd(node, mkdir_cmd)
        scp_cmd = (r'''sshpass -p %(pwd)s scp -oStrictHostKeyChecking=no '''
                   '''-o LogLevel=quiet -r %(src_file)s  '''
                   '''%(user)s@%(hostname)s:%(dst_dir)s/%(dst_file)s '''
                   '''>> %(log)s 2>&1''' %
                   {'user': node.user, 'hostname': node.hostname,
                    'pwd': node.passwd, 'log': node.log,
                    'src_file': src_file, 'dst_dir': dst_dir,
                    'dst_file': dst_file})
        Helper.run_command_on_local(scp_cmd)
        chmod_cmd = (r'''sudo chmod -R %(mode)d %(dst_dir)s/%(dst_file)s''' %
                    {'mode': mode, 'dst_dir': dst_dir, 'dst_file': dst_file})
        Helper.run_command_on_remote_with_passwd(node, chmod_cmd)

    @staticmethod
    def copy_file_from_remote_with_passwd(
        node, src_dir, src_file, dst_dir, mode=777):
        """
        Copy file from remote node to local node,
        create directory if local directory doesn't exist,
        change the file mode as well.
        """
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_local(mkdir_cmd)
        scp_cmd = (r'''sshpass -p %(pwd)s scp -oStrictHostKeyChecking=no '''
                   '''-o LogLevel=quiet %(user)s@%(hostname)s:%(src_dir)s'''
                   '''/%(src_file)s %(dst_dir)s/%(src_file)s >> %(log)s 2>&1'''
                   % {'pwd': node.passwd, 'user': node.user,
                      'hostname': node.hostname, 'log': node.log,
                      'src_dir': src_dir, 'dst_dir': dst_dir,
                      'src_file': src_file})
        Helper.run_command_on_local(scp_cmd)
        chmod_cmd = (r'''sudo chmod -R %(mode)d %(dst_dir)s/%(src_file)s''' %
                    {'mode': mode, 'dst_dir': dst_dir, 'src_file': src_file})
        Helper.run_command_on_local(chmod_cmd)

    @staticmethod
    def run_command_on_remote_with_key(node, command, timeout=600):
        """
        Run cmd on remote node.
        """
        local_cmd = (r'''ssh -t -oStrictHostKeyChecking=no -o '''
                     '''LogLevel=quiet %(user)s@%(hostname)s '''
                     '''"%(remote_cmd)s | tee %(log)s 2>&1"''' %
                     {'hostname': node.hostname, 'log': node.log,
                      'remote_cmd': command, 'user': node.user})
        return Helper.run_command_on_local(local_cmd, timeout)

    @staticmethod
    def copy_dir_to_remote_with_key(node, src_dir, dst_dir):
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_remote_with_key(node, mkdir_cmd)
        scp_cmd = (r'''scp -oStrictHostKeyChecking=no -o LogLevel=quiet '''
                   '''-r %(src_dir)s %(user)s@%(hostname)s:%(dst_dir)s/ '''
                   '''>> %(log)s 2>&1''' %
                   {'hostname': node.hostname, 'log': node.log,
                    'src_dir': src_dir, 'dst_dir': dst_dir, 'user': node.user})
        Helper.run_command_on_local(scp_cmd)

    @staticmethod
    def copy_file_to_remote_with_key(
        node, src_file, dst_dir, dst_file, mode=777):
        """
        Copy file from local node to remote node,
        create directory if remote directory doesn't exist,
        change the file mode as well.
        """
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_remote_with_key(node, mkdir_cmd)
        scp_cmd = (r'''scp -oStrictHostKeyChecking=no -o LogLevel=quiet '''
                   '''-r %(src_file)s %(user)s@%(hostname)s:%(dst_dir)s/'''
                   '''%(dst_file)s >> %(log)s 2>&1''' %
                   {'hostname': node.hostname, 'log': node.log,
                   'src_file': src_file, 'dst_dir': dst_dir,
                   'dst_file': dst_file, 'user': node.user})
        Helper.run_command_on_local(scp_cmd)
        chmod_cmd = (r'''sudo chmod -R %(mode)d %(dst_dir)s/%(dst_file)s''' %
                    {'mode': mode, 'dst_dir': dst_dir, 'dst_file': dst_file})
        Helper.run_command_on_remote_with_key(node, chmod_cmd)

    @staticmethod
    def copy_file_from_remote_with_key(
        node, src_dir, src_file, dst_dir, mode=777):
        """
        Copy file from remote node to local node,
        create directory if local directory doesn't exist,
        change the file mode as well.
        """
        mkdir_cmd = (r'''mkdir -p %(dst_dir)s''' % {'dst_dir': dst_dir})
        Helper.run_command_on_local(mkdir_cmd)
        scp_cmd = (r'''scp -oStrictHostKeyChecking=no -o LogLevel=quiet '''
                   '''%(user)s@%(hostname)s:%(src_dir)s/%(src_file)s '''
                   '''%(dst_dir)s/%(src_file)s >> %(log)s 2>&1''' %
                   {'hostname': node.hostname, 'log': node.log,
                   'src_dir': src_dir, 'dst_dir': dst_dir,
                   'src_file': src_file, 'user': node.user})
        Helper.run_command_on_local(scp_cmd)
        chmod_cmd = (r'''sudo chmod -R %(mode)d %(dst_dir)s/%(src_file)s''' %
                     {'mode': mode, 'dst_dir': dst_dir, 'src_file': src_file})
        Helper.run_command_on_local(chmod_cmd)

    @staticmethod
    def generate_dhcp_reschedule_script(node):
        openrc = const.PACKSTACK_OPENRC
        if node.rhosp:
            openrc = const.RHOSP_OVERCLOUD_OPENRC
        elif node.fuel_cluster_id:
            openrc = const.FUEL_OPENRC
        dhcp_reschedule_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/'''
            '''dhcp_reschedule.sh''' %
            {'setup_node_dir': node.setup_node_dir,
             'generated_script_dir': const.GENERATED_SCRIPT_DIR})
        node.set_dhcp_reschedule_script_path(dhcp_reschedule_script_path)
        if os.path.isfile(dhcp_reschedule_script_path):
            return
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(bash_template_dir)s/dhcp_reschedule.sh''' %
                   {'setup_node_dir': node.setup_node_dir,
                   'deploy_mode': node.deploy_mode,
                   'bash_template_dir': const.BASH_TEMPLATE_DIR}),
                  "r") as dhcp_reschedule_template_file:
            dhcp_reschedule_template = dhcp_reschedule_template_file.read()
            dhcp_reschedule = (dhcp_reschedule_template %
                               {'openrc': openrc,
                                'openstack_release': node.openstack_release})
        with open(dhcp_reschedule_script_path, "w") as dhcp_reschedule_file:
            dhcp_reschedule_file.write(dhcp_reschedule)

    @staticmethod
    def generate_ospurge_script(node):
        openrc = const.PACKSTACK_OPENRC
        if node.rhosp:
            openrc = const.RHOSP_OVERCLOUD_OPENRC
        elif node.fuel_cluster_id:
            openrc = const.FUEL_OPENRC
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(ospurge_template_dir)s/%(ospurge_template)s.sh''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'ospurge_template_dir': const.OSPURGE_TEMPLATE_DIR,
                    'ospurge_template': "purge_all"}),
                  "r") as ospurge_template_file:
            ospurge_template = ospurge_template_file.read()
            ospurge = (ospurge_template % {'openrc': openrc})
        ospurge_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/'''
            '''%(hostname)s_ospurge.sh''' %
            {'setup_node_dir': node.setup_node_dir,
             'generated_script_dir': const.GENERATED_SCRIPT_DIR,
             'hostname': node.hostname})
        with open(ospurge_script_path, "w") as ospurge_file:
            ospurge_file.write(ospurge)
        node.set_ospurge_script_path(ospurge_script_path)

    @staticmethod
    def generate_scripts_for_redhat(node):
        # generate bash script
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(bash_template_dir)s/%(bash_template)s_'''
                   '''%(os_version)s.sh''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'bash_template_dir': const.BASH_TEMPLATE_DIR,
                    'bash_template': const.REDHAT,
                    'os_version': node.os_version}),
                  "r") as bash_template_file:
            bash_template = bash_template_file.read()
            is_controller = False
            if node.role == const.ROLE_NEUTRON_SERVER:
                is_controller = True
            bash = (
                bash_template %
                {'install_ivs': str(node.install_ivs).lower(),
                 'pip_proxy': node.pip_proxy,
                 'install_bsnstacklib': str(node.install_bsnstacklib).lower(),
                 'install_all': str(node.install_all).lower(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'is_controller': str(is_controller).lower(),
                 'deploy_horizon_patch':
                     str(node.deploy_horizon_patch).lower(),
                 'ivs_version': node.ivs_version,
                 'bsnstacklib_version_lower': node.get_bsnstacklib_version_lower(),
                 'bsnstacklib_version_upper': node.get_bsnstacklib_version_upper(),
                 'openstack_release': node.openstack_release,
                 'dst_dir': node.dst_dir,
                 'hostname': node.hostname,
                 'ivs_pkg': node.ivs_pkg,
                 'horizon_patch': node.horizon_patch,
                 'horizon_patch_dir': node.horizon_patch_dir,
                 'horizon_base_dir': node.horizon_base_dir,
                 'ivs_debug_pkg': node.ivs_debug_pkg,
                 'ovs_br': node.get_all_ovs_brs(),
                 'bonds': node.get_all_bonds(),
                 'br-int': const.BR_NAME_INT,
                 'fuel_cluster_id': str(node.fuel_cluster_id),
                 'interfaces': node.get_all_interfaces(),
                 'br_fw_admin': node.br_fw_admin,
                 'pxe_interface': node.pxe_interface,
                 'br_fw_admin_address': node.br_fw_admin_address,
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_all_uplinks(),
                 'rhosp_automate_register':
                     str(node.rhosp_automate_register).lower(),
                 'rhosp_undercloud_dns': str(node.rhosp_undercloud_dns),
                 'rhosp_register_username': str(node.rhosp_register_username),
                 'rhosp_register_passwd': str(node.rhosp_register_passwd),
                 'bond': node.bond,
                 'br_bond': node.br_bond})
        bash_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s'''
            '''/%(hostname)s.sh''' %
            {'setup_node_dir': node.setup_node_dir,
             'generated_script_dir': const.GENERATED_SCRIPT_DIR,
             'hostname': node.hostname})
        with open(bash_script_path, "w") as bash_file:
            bash_file.write(bash)
        node.set_bash_script_path(bash_script_path)

        # generate puppet script
        ivs_daemon_args = (
            const.IVS_DAEMON_ARGS %
            {'inband_vlan': const.INBAND_VLAN,
             'internal_ports': node.get_ivs_internal_ports(),
             'uplink_interfaces': node.get_uplink_intfs_for_ivs()})
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(puppet_template_dir)s/%(puppet_template)s_'''
                   '''%(role)s.pp''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'puppet_template_dir': const.PUPPET_TEMPLATE_DIR,
                    'puppet_template': const.REDHAT,
                    'role': node.role}), "r") as puppet_template_file:
            puppet_template = puppet_template_file.read()
            puppet = (
                puppet_template %
                {'ivs_daemon_args': ivs_daemon_args,
                 'network_vlan_ranges': node.get_network_vlan_ranges(),
                 'bcf_controllers': node.get_controllers_for_neutron(),
                 'bcf_controller_user': node.bcf_controller_user,
                 'bcf_controller_passwd': node.bcf_controller_passwd,
                 'port_ips': node.get_ivs_internal_port_ips(),
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_comma_separated_uplinks(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'neutron_id': node.get_neutron_id(),
                 'uname': node.uname,
                 'bond': node.bond,
                 'mtu': node.uplink_mtu,
                 'keystone_auth_url': node.keystone_auth_url,
                 'keystone_auth_user': node.keystone_auth_user,
                 'keystone_password': node.keystone_password,
                 'keystone_auth_tenant': node.keystone_auth_tenant,
                 'rabbit_hosts': node.rabbit_hosts})
        puppet_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/'''
            '''%(hostname)s.pp''' %
            {'setup_node_dir': node.setup_node_dir,
             'generated_script_dir': const.GENERATED_SCRIPT_DIR,
             'hostname': node.hostname})
        with open(puppet_script_path, "w") as puppet_file:
            puppet_file.write(puppet)
        node.set_puppet_script_path(puppet_script_path)

        if node.role != const.ROLE_NEUTRON_SERVER:
            return

        Helper.generate_ospurge_script(node)
        Helper.generate_dhcp_reschedule_script(node)

    @staticmethod
    def generate_scripts_for_ubuntu(node):
        # generate bash script
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(bash_template_dir)s/%(bash_template)s_'''
                   '''%(os_version)s.sh''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'bash_template_dir': const.BASH_TEMPLATE_DIR,
                    'bash_template': const.UBUNTU,
                    'os_version': node.os_version}),
                  "r") as bash_template_file:
            bash_template = bash_template_file.read()
            is_controller = False
            is_ceph = False
            is_cinder = False
            is_mongo = False
            if node.role == const.ROLE_NEUTRON_SERVER:
                is_controller = True
            if node.role == const.ROLE_CEPH:
                is_ceph = True
            if const.ROLE_CINDER in node.role.lower():
                is_cinder = True
            if node.role == const.ROLE_MONGO:
                is_mongo = True
            bash = (
                bash_template %
                {'install_ivs': str(node.install_ivs).lower(),
                 'pip_proxy': node.pip_proxy,
                 'install_bsnstacklib': str(node.install_bsnstacklib).lower(),
                 'install_all': str(node.install_all).lower(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'is_controller': str(is_controller).lower(),
                 'is_ceph' : str(is_ceph).lower(),
                 'is_cinder': str(is_cinder).lower(),
                 'is_mongo': str(is_mongo).lower(),
                 'deploy_horizon_patch':
                     str(node.deploy_horizon_patch).lower(),
                 'ivs_version': node.ivs_version,
                 'bsnstacklib_version_lower': node.get_bsnstacklib_version_lower(),
                 'bsnstacklib_version_upper': node.get_bsnstacklib_version_upper(),
                 'openstack_release': node.openstack_release,
                 'dst_dir': node.dst_dir,
                 'hostname': node.hostname,
                 'ivs_pkg': node.ivs_pkg,
                 'horizon_patch': node.horizon_patch,
                 'horizon_patch_dir': node.horizon_patch_dir,
                 'horizon_base_dir': node.horizon_base_dir,
                 'ivs_debug_pkg': node.ivs_debug_pkg,
                 'ovs_br': node.get_all_ovs_brs(),
                 'bonds': node.get_all_bonds(),
                 'br-int': const.BR_NAME_INT,
                 'fuel_cluster_id': str(node.fuel_cluster_id),
                 'interfaces': node.get_all_interfaces(),
                 'br_fw_admin': node.br_fw_admin,
                 'pxe_interface': node.pxe_interface,
                 'br_fw_admin_address': node.br_fw_admin_address,
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_all_uplinks(),
                 'bond': node.bond,
                 'br_bond': node.br_bond,
                 'skip_ivs_version_check': str(node.skip_ivs_version_check).lower()})
        bash_script_path = (r'''%(setup_node_dir)s/%(generated_script_dir)s'''
                            '''/%(hostname)s.sh''' %
                            {'setup_node_dir': node.setup_node_dir,
                             'generated_script_dir':
                                 const.GENERATED_SCRIPT_DIR,
                             'hostname': node.hostname})
        with open(bash_script_path, "w") as bash_file:
            bash_file.write(bash)
        node.set_bash_script_path(bash_script_path)

        # generate puppet script
        ivs_daemon_args = (
            const.IVS_DAEMON_ARGS %
            {'inband_vlan': const.INBAND_VLAN,
             'internal_ports': node.get_ivs_internal_ports(),
             'uplink_interfaces': node.get_uplink_intfs_for_ivs()})
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(puppet_template_dir)s/%(puppet_template)s_'''
                   '''%(role)s.pp''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'puppet_template_dir': const.PUPPET_TEMPLATE_DIR,
                    'puppet_template': const.UBUNTU,
                    'role': node.role}), "r") as puppet_template_file:
            puppet_template = puppet_template_file.read()
            puppet = (
                puppet_template %
                {'ivs_daemon_args': ivs_daemon_args,
                 'network_vlan_ranges': node.get_network_vlan_ranges(),
                 'bcf_controllers': node.get_controllers_for_neutron(),
                 'bcf_controller_user': node.bcf_controller_user,
                 'bcf_controller_passwd': node.bcf_controller_passwd,
                 'port_ips': node.get_ivs_internal_port_ips(),
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_comma_separated_uplinks(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'neutron_id': node.get_neutron_id(),
                 'uname': node.uname,
                 'mtu': node.uplink_mtu,
                 'keystone_auth_url': node.keystone_auth_url,
                 'keystone_auth_user': node.keystone_auth_user,
                 'keystone_password': node.keystone_password,
                 'keystone_auth_tenant': node.keystone_auth_tenant,
                 'bond': node.bond})
        puppet_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/%(hostname)s.pp'''
            % {'setup_node_dir': node.setup_node_dir,
               'generated_script_dir': const.GENERATED_SCRIPT_DIR,
               'hostname': node.hostname})
        with open(puppet_script_path, "w") as puppet_file:
            puppet_file.write(puppet)
        node.set_puppet_script_path(puppet_script_path)

        if node.role != const.ROLE_NEUTRON_SERVER:
            return

        Helper.generate_ospurge_script(node)
        Helper.generate_dhcp_reschedule_script(node)

    @staticmethod
    def generate_scripts_for_centos(node):

        # generate bash script
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(bash_template_dir)s/%(bash_template)s_'''
                   '''%(os_version)s.sh''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'bash_template_dir': const.BASH_TEMPLATE_DIR,
                    'bash_template': const.CENTOS,
                    'os_version': node.os_version}),
                  "r")as bash_template_file:
            bash_template = bash_template_file.read()
            is_controller = False
            if node.role == const.ROLE_NEUTRON_SERVER:
                is_controller = True
            bash = (
                bash_template %
                {'install_ivs': str(node.install_ivs).lower(),
                 'pip_proxy': node.pip_proxy,
                 'install_bsnstacklib': str(node.install_bsnstacklib).lower(),
                 'install_all': str(node.install_all).lower(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'is_controller': str(is_controller).lower(),
                 'deploy_horizon_patch':
                     str(node.deploy_horizon_patch).lower(),
                 'ivs_version': node.ivs_version,
                 'bsnstacklib_version_lower': node.get_bsnstacklib_version_lower(),
                 'bsnstacklib_version_upper': node.get_bsnstacklib_version_upper(),
                 'openstack_release': node.openstack_release,
                 'dst_dir': node.dst_dir,
                 'hostname': node.hostname,
                 'ivs_pkg': node.ivs_pkg,
                 'horizon_patch': node.horizon_patch,
                 'horizon_patch_dir': node.horizon_patch_dir,
                 'horizon_base_dir': node.horizon_base_dir,
                 'ivs_debug_pkg': node.ivs_debug_pkg,
                 'ovs_br': node.get_all_ovs_brs(),
                 'bonds': node.get_all_bonds(),
                 'br-int': const.BR_NAME_INT,
                 'fuel_cluster_id': str(node.fuel_cluster_id),
                 'interfaces': node.get_all_interfaces(),
                 'br_fw_admin': node.br_fw_admin,
                 'pxe_interface': node.pxe_interface,
                 'br_fw_admin_address': node.br_fw_admin_address,
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_all_uplinks(),
                 'bond': node.bond,
                 'br_bond': node.br_bond,
                 'skip_ivs_version_check': str(node.skip_ivs_version_check).lower()})
        bash_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/%(hostname)s.sh'''
            % {'setup_node_dir': node.setup_node_dir,
               'generated_script_dir': const.GENERATED_SCRIPT_DIR,
               'hostname': node.hostname})
        with open(bash_script_path, "w") as bash_file:
            bash_file.write(bash)
        node.set_bash_script_path(bash_script_path)

        # generate puppet script
        ivs_daemon_args = (
            const.IVS_DAEMON_ARGS %
            {'inband_vlan': const.INBAND_VLAN,
             'internal_ports': node.get_ivs_internal_ports(),
             'uplink_interfaces': node.get_uplink_intfs_for_ivs()})
        with open((r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                   '''%(puppet_template_dir)s/%(puppet_template)s_'''
                   '''%(role)s.pp''' %
                   {'setup_node_dir': node.setup_node_dir,
                    'deploy_mode': node.deploy_mode,
                    'puppet_template_dir': const.PUPPET_TEMPLATE_DIR,
                    'puppet_template': const.CENTOS,
                    'role': node.role}), "r") as puppet_template_file:
            puppet_template = puppet_template_file.read()
            puppet = (
                puppet_template %
                {'ivs_daemon_args': ivs_daemon_args,
                 'network_vlan_ranges': node.get_network_vlan_ranges(),
                 'bcf_controllers': node.get_controllers_for_neutron(),
                 'bcf_controller_user': node.bcf_controller_user,
                 'bcf_controller_passwd': node.bcf_controller_passwd,
                 'port_ips': node.get_ivs_internal_port_ips(),
                 'default_gw': node.get_default_gw(),
                 'uplinks': node.get_comma_separated_uplinks(),
                 'deploy_dhcp_agent': str(node.deploy_dhcp_agent).lower(),
                 'deploy_l3_agent': str(node.deploy_l3_agent).lower(),
                 'neutron_id': node.get_neutron_id(),
                 'selinux_mode': node.selinux_mode,
                 'br_int': const.BR_NAME_INT,
                 'network_vlan_ranges': node.get_network_vlan_ranges(),
                 'br_mappings': node.get_bridge_mappings(),
                 'uname': node.uname,
                 'mtu': node.uplink_mtu,
                 'keystone_auth_url': node.keystone_auth_url,
                 'keystone_auth_user': node.keystone_auth_user,
                 'keystone_password': node.keystone_password,
                 'keystone_auth_tenant': node.keystone_auth_tenant,
                 'bond': node.bond})
        puppet_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s/%(hostname)s.pp'''
            % {'setup_node_dir': node.setup_node_dir,
               'generated_script_dir': const.GENERATED_SCRIPT_DIR,
               'hostname': node.hostname})
        with open(puppet_script_path, "w") as puppet_file:
            puppet_file.write(puppet)
        node.set_puppet_script_path(puppet_script_path)

        # generate selinux script
        selinux_script_path = (
            r'''%(setup_node_dir)s/%(generated_script_dir)s'''
            '''/%(hostname)s.te''' %
            {'setup_node_dir': node.setup_node_dir,
             'generated_script_dir': const.GENERATED_SCRIPT_DIR,
             'hostname': node.hostname})
        subprocess.call(r'''cp %(setup_node_dir)s/%(deploy_mode)s/'''
                        '''%(selinux_template_dir)s/%(selinux_template)s.'''
                        '''te %(selinux_script_path)s''' %
                        {'setup_node_dir': node.setup_node_dir,
                         'deploy_mode': node.deploy_mode,
                         'selinux_template_dir': const.SELINUX_TEMPLATE_DIR,
                         'selinux_template': const.CENTOS,
                         'selinux_script_path': selinux_script_path},
                        shell=True)
        node.set_selinux_script_path(selinux_script_path)

        # generate ospurge script
        if node.role != const.ROLE_NEUTRON_SERVER:
            return

        Helper.generate_ospurge_script(node)
        Helper.generate_dhcp_reschedule_script(node)

    @staticmethod
    def __load_node_yaml_config__(node_config, env):
        if 'role' not in node_config:
            node_config['role'] = env.role
        if 'skip' not in node_config:
            node_config['skip'] = env.skip
        if 'deploy_mode' not in node_config:
            node_config['deploy_mode'] = env.deploy_mode
        if 'os' not in node_config:
            node_config['os'] = env.os
        if 'os_version' not in node_config:
            node_config['os_version'] = env.os_version
        if 'user' not in node_config:
            node_config['user'] = env.user
        if 'passwd' not in node_config:
            node_config['passwd'] = env.passwd
        if 'uplink_interfaces' not in node_config:
            node_config['uplink_interfaces'] = env.uplink_interfaces
        if 'install_ivs' not in node_config:
            node_config['install_ivs'] = env.install_ivs
        if 'install_bsnstacklib' not in node_config:
            node_config['install_bsnstacklib'] = env.install_bsnstacklib
        if 'install_all' not in node_config:
            node_config['install_all'] = env.install_all
        if 'deploy_dhcp_agent' not in node_config:
            node_config['deploy_dhcp_agent'] = env.deploy_dhcp_agent
        if 'deploy_l3_agent' not in node_config:
            node_config['deploy_l3_agent'] = env.deploy_l3_agent
        if 'uplink_mtu' not in node_config:
            node_config['uplink_mtu'] = env.uplink_mtu
        return node_config

    @staticmethod
    def load_nodes_from_yaml(node_yaml_config_map, env):
        """
        Parse yaml file and return a dictionary
        """
        node_dic = {}
        if node_yaml_config_map is None:
            return node_dic
        for hostname, node_yaml_config in node_yaml_config_map.iteritems():
            node_yaml_config = Helper.__load_node_yaml_config__(
                node_yaml_config, env)

            node = Node(node_yaml_config, env)
            if not Helper.is_connected(node):
                continue
            if node.skip:
                continue

            node_yaml_config['old_ivs_version'] = None
            if node_yaml_config['deploy_mode'] == const.T6:
                # get existing ivs version
                output, errors = (
                    Helper.run_command_on_remote_with_passwd_without_timeout(
                        node_yaml_config['hostname'], node_yaml_config['user'],
                        node_yaml_config['passwd'], 'ivs --version'))
                if errors or not output:
                    node_yaml_config['skip'] = True
                    node_yaml_config['error'] = (
                        "Fail to retrieve ivs version from %(hostname)s" %
                        {'hostname': node_yaml_config['hostname']})
                if output and 'command not found' not in output:
                    node_yaml_config['old_ivs_version'] = output.split()[1]

            node = Node(node_yaml_config, env)
            # copy dpid.py to remote node
            safe_print("Copy dpid.py to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                '''%(python_template_dir)s/dpid.py''' %
                {'setup_node_dir': node.setup_node_dir,
                 'deploy_mode': node.deploy_mode,
                 'python_template_dir': const.PYTHON_TEMPLATE_DIR},
                node.dst_dir, 'dpid.py')
            # get dpid mac
            node_yaml_config['mac'] = Helper.run_command_on_remote(node,
                "python %s/dpid.py" % node.dst_dir)

            uname = Helper.get_uname(node, node_yaml_config)
            if uname:
                node_yaml_config['uname'] = uname
                node = Node(node_yaml_config, env)
                node_dic[node.hostname] = node
        return node_dic

    @staticmethod
    def __load_fuel_evn_setting__(fuel_cluster_id):
        try:
            safe_print("Retrieving general Fuel settings\n")
            cmd = (r'''fuel --json --env %(fuel_cluster_id)s settings -d''' %
                  {'fuel_cluster_id': fuel_cluster_id})
            output, errors = Helper.run_command_on_local_without_timeout(cmd)
        except Exception as e:
            raise Exception("Error encountered trying to execute the Fuel CLI"
                            "\n%(e)s\n" % {'e': e})
        if errors and 'DEPRECATION WARNING' not in errors:
            raise Exception("Error Loading cluster %(fuel_cluster_id)s\n"
                            "%(errors)s\n"
                            % {'fuel_cluster_id': str(fuel_cluster_id),
                               'errors': errors})
        try:
            path = output.split('downloaded to ')[1].rstrip()
        except (IndexError, AttributeError):
            raise Exception("Could not download fuel settings: %(output)s\n"
                            % {'output': output})
        try:
            fuel_settings = json.loads(open(path, 'r').read())
        except Exception as e:
            raise Exception("Error parsing fuel json settings.\n%(e)s\n"
                            % {'e': e})
        return fuel_settings

    @staticmethod
    def __load_rhosp_node__(hostname, role, node_yaml_config_map, env):
        node_config = {}
        node_yaml_config = node_yaml_config_map.get(hostname)
        if node_yaml_config:
            node_config = Helper.__load_node_yaml_config__(
                node_yaml_config, env)
        elif not env.deploy_to_specified_nodes_only:
            node_config = Helper.__load_node_yaml_config__(node_config, env)
        else:
            return None
        node_config['hostname'] = hostname
        node_config['role'] = role

        #parse /etc/os-net-config/config.json
        node = Node(node_config, env)
        subprocess.call("rm -f /tmp/config.json", shell=True)
        Helper.copy_file_from_remote(node, "/etc/os-net-config",
                                     "config.json", "/tmp")
        if not os.path.isfile("/tmp/config.json"):
            safe_print("Error retrieving config for node %(hostname)s:\n"
                       % {'hostname': node_config['hostname']})
            return None
        try:
            data = open("/tmp/config.json").read()
            node_json_config = json.loads(data)
        except Exception as e:
            safe_print("Error parsing node %(hostname)s json file:\n%(e)s\n"
                       % {'hostname': node_config['hostname'], 'e': e})
            return None

        # get ovs bridge and bond
        node_config['br_bond'] = str(
            node_json_config['network_config'][0]['name'])
        members = node_json_config['network_config'][0]['members']
        for member in members:
            if 'name' in member:
                node_config['bond'] = member['name']
                break

        # get ovs uplinks
        uplink_cmd = (r'''sudo ovs-appctl bond/list | grep -v slaves '''
                      '''| grep %(bond)s''' %
                      {'bond': node_config['bond']})
        output, error = Helper.run_command_on_remote_without_timeout(
            node, uplink_cmd)
        if error:
            safe_print("Error getting node %(hostname)s uplinks:\n%(error)s\n"
                       % {'hostname': node_config['hostname'],
                          'error': error})
            return None
        elif output:
            node_config['uplink_interfaces'] = (
                output.replace(',', ' ').split()[3:])
        else:
            # ovs bond has been removed, not the first time running this script
            uplink_cmd = (r'''sudo cat /proc/net/bonding/%(bond)s | '''
                          '''grep Slave | grep Interface | cut -c18-''' %
                          {'bond': node_config['bond']})
            output, error = Helper.run_command_on_remote_without_timeout(
                node, uplink_cmd)
            if error:
                safe_print(
                    "Error getting node %(hostname)s uplinks:\n%(error)s\n"
                    % {'hostname': node_config['hostname'], 'error': error})
                return None
            node_config['uplink_interfaces'] = output.split()

        # get uname
        uname = Helper.get_uname(node, node_config)
        if uname:
            # TODO parse other vlans and bridges
            # TODO get ivs version for t6
            node_config['uname'] = uname
            node = Node(node_config, env)
            return node
        else:
            return None

    @staticmethod
    def __load_fuel_node__(hostname, role, node_yaml_config_map, env):
        node_config = {}
        node_yaml_config = node_yaml_config_map.get(hostname)
        if node_yaml_config:
            node_config = Helper.__load_node_yaml_config__(
                node_yaml_config, env)
        elif not env.deploy_to_specified_nodes_only:
            node_config = Helper.__load_node_yaml_config__(node_config, env)
        else:
            return None
        node_config['hostname'] = hostname
        node_config['role'] = role
        if ((role != const.ROLE_NEUTRON_SERVER) and
                (role != const.ROLE_COMPUTE) and
                (const.ROLE_CEPH not in role.lower()) and
                (const.ROLE_CINDER not in role.lower()) and
                (role != const.ROLE_MONGO)):
            node_config['skip'] = True
            node_config['error'] = "node role is %s" % (role)

        # get node operating system information
        os_info, errors = (
            Helper.run_command_on_remote_with_key_without_timeout(
                node_config['hostname'],
                node_config['user'], 'python -mplatform'))
        if errors or (not os_info):
            safe_print("Error retrieving operating system info from node "
                       "%(hostname)s:\n%(errors)s\n"
                       % {'hostname': node_config['hostname'],
                          'errors': errors})
            return None
        try:
            os_and_version = os_info.split('with-')[1].split('-')
            node_config['os'] = os_and_version[0]
            node_config['os_version'] = os_and_version[1]
        except Exception as e:
            safe_print("Error parsing node %(hostname)s operating "
                       "system info:\n%(e)s\n"
                       % {'hostname': node_config['hostname'], 'e': e})
            return None

        # get node /etc/astute.yaml
        node_yaml, errors = (
            Helper.run_command_on_remote_with_key_without_timeout(
                node_config['hostname'],
                node_config['user'], 'cat /etc/astute.yaml'))
        if errors or not node_yaml:
            safe_print("Error retrieving config for node "
                       "%(hostname)s:\n%(errors)s\n"
                       % {'hostname': node_config['hostname'],
                          'errors': errors})
            return None
        try:
            node_yaml_config = yaml.load(node_yaml)
        except Exception as e:
            safe_print("Error parsing node %(hostname)s yaml file:\n%(e)s\n"
                       % {'hostname': node_config['hostname'], 'e': e})
            return None

        # get existing ivs version
        node_config['old_ivs_version'] = None
        output, errors = (
            Helper.run_command_on_remote_with_key_without_timeout(
                node_config['hostname'],
                node_config['user'], 'ivs --version'))
        if errors or not output:
            safe_print("Error retrieving ivs version from node "
                       "%(hostname)s:\n%(errors)s\n"
                       % {'hostname': node_config['hostname'],
                          'errors': errors})
            return None
        if 'command not found' not in output:
            node_config['old_ivs_version'] = output.split()[1]

        # physnet and vlan range
        physnets = node_yaml_config['quantum_settings']['L2']['phys_nets']
        for physnet, physnet_detail in physnets.iteritems():
            env.set_physnet(physnet)
            vlans = physnet_detail['vlan_range'].strip().split(':')
            env.set_lower_vlan(vlans[0])
            env.set_upper_vlan(vlans[1])
            # we deal with only the first physnet
            break

        # get bond bridge attached by br_prv
        roles = node_yaml_config['network_scheme']['roles']
        br_prv = roles[const.BR_KEY_PRIVATE]
        trans = node_yaml_config['network_scheme']['transformations']
        for tran in trans:
            if (tran['action'] != 'add-patch'):
                continue
            if (br_prv not in tran['bridges']):
                continue
            bridges = list(tran['bridges'])
            bridges.remove(br_prv)
            node_config['br_bond'] = bridges[0]
            break

        # get bond name
        for tran in trans:
            if (tran['action'] != 'add-bond'):
                continue
            if (node_config['br_bond'] != tran.get('bridge')):
                continue
            node_config['bond'] = tran['name']
            break

        # bond intfs
        for tran in trans:
            if (tran['action'] == 'add-bond'
                and tran['bridge'] == node_config['br_bond']):
                node_config['uplink_interfaces'] = tran['interfaces']
                break

        # to support sr-iov, we don't use bond
        if not node_config.get('bond'):
            for tran in trans:
                if (tran['action'] == 'add-port'
                    and tran['bridge'] == node_config['br_bond']):
                    node_config['bond'] = tran['name'] 
                    node_config['uplink_interfaces'] = []
                    node_config['uplink_interfaces'].append(tran['name'])
                    break
            

        # Fuel 7 doesn't have vlan info in endpoints,
        # Build bridge vlan from tran
        bridge_vlan_map = {}
        for tran in trans:
            if (tran['action'] == 'add-port' and
                    node_config['bond'] in tran['name'] and
                    '.' in tran['name']):
                bridge_vlan_map[tran['bridge']] = (
                    int(tran['name'].split('.')[1]))
        node_config['bridge_vlan_map'] = bridge_vlan_map

        # get br-fw-admin information
        endpoints = node_yaml_config['network_scheme']['endpoints']
        node_config['br_fw_admin'] = roles[const.BR_KEY_FW_ADMIN]
        ip = endpoints[node_config['br_fw_admin']]['IP']
        if ip == const.NONE_IP:
            node_config['br_fw_admin_address'] = None
        else:
            node_config['br_fw_admin_address'] = ip[0]
        for tran in trans:
            if (tran['action'] != 'add-port'):
                continue
            if (tran.get('bridge') != node_config['br_fw_admin']):
                continue
            node_config['pxe_interface'] = tran['name']
            break

        # get bridge ip, vlan and construct bridge obj
        bridges = set()
        bridge_names = set()
        for br_key, br_name in roles.iteritems():
            if br_name == node_config['br_fw_admin']:
                continue

            vlan = None
            vendor_specific = endpoints[br_name].get('vendor_specific')
            if vendor_specific:
                vlan = vendor_specific.get('vlans')
                phy_interfaces = vendor_specific.get('phy_interfaces')
                if phy_interfaces:
                    set1 = set(node_config['uplink_interfaces'])
                    set2 = set(phy_interfaces)
                    issuperset = set1.issuperset(set2)
                    issubset = set2.issubset(set1)
                    if not (issuperset and issubset):
                        # we don't touch the bridge which doesn't use bond
                        continue

            if not vlan:
                vlan = node_config['bridge_vlan_map'].get(br_name)
            ip = endpoints[br_name].get('IP')
            if (not ip) or (ip == const.NONE_IP):
                ip = None
            else:
                ip = ip[0]
            bridge = Bridge(br_key, br_name, ip, vlan)
            bridges.add(bridge)
            bridge_names.add(br_name)

            # get default gw, most likely on br-ex
            gw = endpoints[br_name].get('gateway')
            if gw:
                node_config['ex_gw'] = gw
        node_config['bridges'] = bridges

        # get non-bond, non-pxe interfaces,
        # will be most likely tagged
        tagged_intfs = []
        for tran in trans:
            if (tran['action'] != 'add-port'
                or tran['name'] == node_config['pxe_interface']
                or tran['bridge'] in bridge_names):
                    continue
            tagged_intfs.append(tran['name'])
        node_config['tagged_intfs'] = tagged_intfs

        node = Node(node_config, env)
        if node.skip:
            return None
        # copy dpid.py to remote node
        safe_print("Copy dpid.py to %(hostname)s\n" %
                   {'hostname': node.fqdn})
        Helper.copy_file_to_remote(
            node,
            r'''%(setup_node_dir)s/%(deploy_mode)s/'''
            '''%(python_template_dir)s/dpid.py''' %
            {'setup_node_dir': node.setup_node_dir,
             'deploy_mode': node.deploy_mode,
             'python_template_dir': const.PYTHON_TEMPLATE_DIR},
            node.dst_dir, 'dpid.py')
        # get dpid mac
        node_config['mac'] = Helper.run_command_on_remote(node,
            "python %s/dpid.py" % node.dst_dir)

        uname = Helper.get_uname(node, node_config)
        if uname:
            node_config['uname'] = uname
            node = Node(node_config, env)
            return node
        else:
            return None

    @staticmethod
    def load_nodes_from_fuel(node_yaml_config_map, env):
        Helper.__load_fuel_evn_setting__(env.fuel_cluster_id)

        safe_print("Retrieving list of Fuel nodes\n")
        cmd = (r'''fuel nodes --env %(fuel_cluster_id)s --json''' %
               {'fuel_cluster_id': str(env.fuel_cluster_id)})
        node_list, errors = Helper.run_command_on_local_without_timeout(cmd)
        if errors and 'DEPRECATION WARNING' not in errors:
            raise Exception("Error Loading node list %(fuel_cluster_id)s:\n"
                            "%(errors)s\n"
                            % {'fuel_cluster_id': env.fuel_cluster_id,
                               'errors': errors})

        node_list = json.loads(node_list)
        node_dic = {}
        membership_rules = {}
        try:
            for n in node_list:
                hostname = n.get('ip')
                role = n.get('roles')
                online = n.get('online')

                if not online or (const.ROLE_NEUTRON_SERVER not in role and
                                  const.ROLE_COMPUTE not in role and
                                  const.ROLE_CEPH not in role.lower() and
                                  const.ROLE_CINDER not in role.lower() and
                                  const.ROLE_MONGO not in role):
                    continue

                if const.ROLE_NEUTRON_SERVER in role:
                    role = const.ROLE_NEUTRON_SERVER
                elif const.ROLE_COMPUTE in role:
                    role = const.ROLE_COMPUTE
                elif const.ROLE_CEPH in role.lower():
                    role = const.ROLE_CEPH
                elif const.ROLE_CINDER in role.lower():
                    role = const.ROLE_CINDER
                elif const.ROLE_MONGO in role:
                    role = const.ROLE_MONGO
                else:
                    continue

                node = Helper.__load_fuel_node__(
                    hostname, role, node_yaml_config_map, env)
                if (not node) or (not node.hostname):
                    continue
                node_dic[node.hostname] = node

                # get node bridges
                if node.deploy_mode == const.T5:
                    continue
                for br in node.bridges:
                    if (not br.br_vlan) or (br.br_key == const.BR_KEY_PRIVATE):
                        continue
                    rule = MembershipRule(br.br_key, br.br_vlan,
                                          node.bcf_openstack_management_tenant,
                                          node.fuel_cluster_id)
                    membership_rules[rule.segment] = rule

        except IndexError:
            raise Exception("Could not parse node list:\n%(node_list)s\n"
                            % {'node_list': node_list})
        return node_dic, membership_rules

    @staticmethod
    def load_nodes_from_rhosp(node_yaml_config_map, env):
        safe_print("Retrieving list of rhosp nodes\n")
        cmd = (r'''source %(stackrc)s; nova list'''
               % {'stackrc': const.RHOSP_UNDERCLOUD_OPENRC})
        node_list, errors = Helper.run_command_on_local_without_timeout(cmd)
        if errors:
            raise Exception("Error Loading node list from rhosp:\n%(errors)s\n"
                            % {'errors': errors})

        node_dic = {}
        membership_rules = {}
        try:
            lines = [l for l in node_list.splitlines()
                     if '----' not in l and 'Status' not in l]
            for line in lines:
                hostname = str(
                    netaddr.IPAddress(line.split('|')[6].strip()
                    .split('=')[1]))
                role = str(line.split('|')[2].strip().split('-')[1]).lower()
                online = str(line.split('|')[3].strip())
                if online.lower() != 'active':
                    continue
                node = Helper.__load_rhosp_node__(
                    hostname, role, node_yaml_config_map, env)
                if (not node) or (not node.hostname):
                    continue
                node_dic[node.hostname] = node

                # get node bridges
                if node.deploy_mode == const.T5:
                    continue
                for br in node.bridges:
                    if (not br.br_vlan) or (br.br_key == const.BR_KEY_PRIVATE):
                        continue
                    rule = MembershipRule(br.br_key, br.br_vlan,
                                          node.bcf_openstack_management_tenant,
                                          node.fuel_cluster_id)
                    membership_rules[rule.segment] = rule
        except IndexError:
            raise Exception("Could not parse node list:\n%(node_list)s\n"
                            % {'node_list': node_list})
        return node_dic, membership_rules

    @staticmethod
    def load_nodes(nodes_yaml_config, env):
        node_yaml_config_map = {}
        if nodes_yaml_config is not None:
            for node_yaml_config in nodes_yaml_config:
                # we always use ip address as the hostname
                try:
                    node_yaml_config['hostname'] = socket.gethostbyname(
                        node_yaml_config['hostname'])
                except Exception:
                    continue
                try:
                    node_yaml_config['fqdn'] = socket.gethostbyaddr(
                        node_yaml_config['hostname'])[0]
                except Exception:
                    node_yaml_config['fqdn'] = node_yaml_config['hostname']
                node_yaml_config_map[node_yaml_config['hostname']] = (
                    node_yaml_config)
        if env.fuel_cluster_id is None and not env.rhosp:
            return Helper.load_nodes_from_yaml(node_yaml_config_map, env)
        elif env.fuel_cluster_id:
            node_dic, membership_rules = Helper.load_nodes_from_fuel(
                node_yaml_config_map, env)
            for br_key, rule in membership_rules.iteritems():
                RestLib.program_segment_and_membership_rule(
                    env.bcf_master, env.bcf_cookie, rule,
                    env.bcf_openstack_management_tenant)
            return node_dic
        elif env.rhosp:
            # TODO: no longer supported after BCF 3.5. We moved to
            # the integrated solution with RHOSP8
            node_dic, membership_rules = Helper.load_nodes_from_rhosp(
                node_yaml_config_map, env)
            for br_key, rule in membership_rules.iteritems():
                RestLib.program_segment_and_membership_rule(
                    env.bcf_master, env.bcf_cookie, rule,
                    env.bcf_openstack_management_tenant)
            return node_dic

    @staticmethod
    def common_setup_node_preparation(env):
        # clean up from previous installation
        setup_node_dir = env.setup_node_dir
        subprocess.call("sudo mkdir -p %(setup_node_dir)s/%(generated_script)s"
                        % {'setup_node_dir': setup_node_dir,
                           'generated_script': const.GENERATED_SCRIPT_DIR},
                        shell=True)
        subprocess.call("sudo chmod -R 777 %(setup_node_dir)s" %
                       {'setup_node_dir': setup_node_dir}, shell=True)
        subprocess.call("rm -rf ~/.ssh/known_hosts", shell=True)
        subprocess.call("sudo rm -rf %(log)s" %
                        {'log': const.LOG_FILE}, shell=True)
        subprocess.call("sudo touch %(log)s" %
                        {'log': const.LOG_FILE}, shell=True)
        subprocess.call("sudo chmod 777 %(log)s" %
                        {'log': const.LOG_FILE}, shell=True)
        subprocess.call("sudo rm -rf %(setup_node_dir)s/*ivs*.rpm" %
                        {'setup_node_dir': setup_node_dir}, shell=True)
        subprocess.call("sudo rm -rf %(setup_node_dir)s/*ivs*.deb" %
                        {'setup_node_dir': setup_node_dir}, shell=True)
        subprocess.call("sudo rm -rf %(setup_node_dir)s/*.tar.gz" %
                        {'setup_node_dir': setup_node_dir}, shell=True)
        subprocess.call("sudo rm -rf %(setup_node_dir)s/pkg" %
                        {'setup_node_dir': setup_node_dir}, shell=True)
        subprocess.call("sudo rm -rf %(setup_node_dir)s/%(generated_script)s/*"
                        % {'setup_node_dir': setup_node_dir,
                           'generated_script': const.GENERATED_SCRIPT_DIR},
                        shell=True)

        # wget ivs packages
        if env.deploy_mode == const.T6:
            code_web = 1
            code_local = 1
            for pkg_type, url in env.ivs_url_map.iteritems():
                if 'http://' in url or 'https://' in url:
                    code_web = subprocess.call(
                        "wget --no-check-certificate %(url)s -P "
                        "%(setup_node_dir)s" %
                        {'url': url, 'setup_node_dir': setup_node_dir},
                        shell=True)
            for pkg_type, url in env.ivs_url_map.iteritems():
                if os.path.isfile(url):
                    code_local = subprocess.call(
                        "cp %(url)s %(setup_node_dir)s" %
                        {'url': url, 'setup_node_dir': setup_node_dir},
                        shell=True)
            if code_web != 0 and code_local != 0:
                safe_print(
                    "Required ivs packages are not correctly downloaded.\n")
                exit(1)
            if env.ivs_pkg_map.get('tar'):
                tar_path = ("%(setup_node_dir)s/%(targz)s" %
                            {'setup_node_dir': setup_node_dir,
                             'targz': env.ivs_pkg_map.get('tar')})
                code_tar = subprocess.call(
                    "tar -xzvf %(tar_path)s -C %(setup_node_dir)s" %
                    {'tar_path': tar_path,
                     'setup_node_dir': setup_node_dir},
                    shell=True)
                if code_tar != 0:
                    safe_print("Required ivs packages are not correctly "
                               "downloaded.\n")
                    exit(1)
                for ivs_pkg_dir in const.IVS_TAR_PKG_DIRS:
                    for pkg in os.listdir("%s/%s" % (setup_node_dir,
                                                     ivs_pkg_dir)):
                        if not os.path.isfile("%s/%s/%s" % (setup_node_dir,
                                                            ivs_pkg_dir, pkg)):
                            continue
                        env.set_ivs_pkg_map(pkg)
                        subprocess.call(
                            "cp %(setup_node_dir)s/%(ivs_pkg_dir)s/%(pkg)s "
                            "%(setup_node_dir)s" %
                            {'setup_node_dir': setup_node_dir,
                             'ivs_pkg_dir': ivs_pkg_dir,
                             'pkg': pkg},
                            shell=True)

        # wget horizon patch
        code_web = 1
        code_local = 1
        url = env.horizon_patch_url
        if 'http://' in url or 'https://' in url:
            code_web = subprocess.call(
                "wget --no-check-certificate %(url)s -P %(setup_node_dir)s" %
                {'url': url, 'setup_node_dir': setup_node_dir}, shell=True)
        if os.path.isfile(url):
            code_local = subprocess.call("cp %(url)s %(setup_node_dir)s" %
                                         {'url': url,
                                          'setup_node_dir': setup_node_dir},
                                         shell=True)
        if env.deploy_horizon_patch and code_web != 0 and code_local != 0:
            safe_print(
                "Required horizon packages are not correctly downloaded.\n")
            exit(1)

        # prepare for rhosp7
        if env.rhosp:
            subprocess.call("sudo sysctl -w net.ipv4.ip_forward=1", shell=True)
            subprocess.call(
                r'''sudo iptables -t nat -A POSTROUTING -o '''
                '''%(external)s -j MASQUERADE''' %
                {'external': env.rhosp_installer_management_interface},
                shell=True)
            subprocess.call(
                r'''sudo iptables -A FORWARD -i %(external)s '''
                '''-o %(internal)s -m state --state RELATED,ESTABLISHED '''
                '''-j ACCEPT''' %
                {'external': env.rhosp_installer_management_interface,
                 'internal': env.rhosp_installer_pxe_interface}, shell=True)
            subprocess.call(
                r'''sudo iptables -A FORWARD -i %(internal)s -o '''
                '''%(external)s -j ACCEPT''' %
                {'external': env.rhosp_installer_management_interface,
                 'internal': env.rhosp_installer_pxe_interface}, shell=True)

    @staticmethod
    def update_last_log(node):
        Helper.run_command_on_remote_without_timeout(
            node, "sudo chmod -R 777 %s" % node.log)
        last_log, error = Helper.run_command_on_remote_without_timeout(
            node, "sudo tail -n 1 %s" % node.log)
        if last_log:
            node.set_last_log(last_log.strip())
        return node

    @staticmethod
    def run_command_on_remote_without_timeout(node, command):
        if node.rhosp:
            return Helper.run_command_on_remote_with_key_without_timeout(
                node.hostname, node.user, command)
        elif node.fuel_cluster_id:
            return Helper.run_command_on_remote_with_key_without_timeout(
                node.hostname, node.user, command)
        else:
            return Helper.run_command_on_remote_with_passwd_without_timeout(
                node.hostname, node.user, node.passwd, command)

    @staticmethod
    def run_command_on_remote(node, command, timeout=600):
        if node.rhosp:
            return Helper.run_command_on_remote_with_key(node, command, timeout)
        elif node.fuel_cluster_id:
            return Helper.run_command_on_remote_with_key(node, command, timeout)
        else:
            return Helper.run_command_on_remote_with_passwd(node, command, timeout)

    @staticmethod
    def copy_file_from_remote(node, src_dir, src_file, dst_dir, mode=777):
        if node.rhosp:
            Helper.copy_file_from_remote_with_key(
                node, src_dir, src_file, dst_dir, mode)
        elif node.fuel_cluster_id:
            Helper.copy_file_from_remote_with_key(
                node, src_dir, src_file, dst_dir, mode)
        else:
            Helper.copy_file_from_remote_with_passwd(
                node, src_dir, src_file, dst_dir, mode)

    @staticmethod
    def copy_dir_to_remote(node, src_dir, dst_dir):
        if node.rhosp:
            Helper.copy_dir_to_remote_with_key(node, src_dir, dst_dir)
        elif node.fuel_cluster_id:
            Helper.copy_dir_to_remote_with_key(node, src_dir, dst_dir)
        else:
            Helper.copy_dir_to_remote_with_passwd(node, src_dir, dst_dir)

    @staticmethod
    def copy_file_to_remote(node, src_file, dst_dir, dst_file, mode=777):
        if node.rhosp:
            Helper.copy_file_to_remote_with_key(
                node, src_file, dst_dir, dst_file, mode)
        elif node.fuel_cluster_id:
            Helper.copy_file_to_remote_with_key(
                node, src_file, dst_dir, dst_file, mode)
        else:
            Helper.copy_file_to_remote_with_passwd(
                node, src_file, dst_dir, dst_file, mode)

    @staticmethod
    def copy_dhcp_scheduler_from_controllers(controller_nodes):
        if len(controller_nodes) == 0:
            return
        controller_node = controller_nodes[0]
        if controller_node.openstack_release != 'juno':
            # we only patch juno
            return
        dhcp_py = "dhcp_agent_scheduler.py"
        src_path, error = Helper.run_command_on_remote_without_timeout(
            controller_node, "find /usr/lib -name %s" % dhcp_py)
        if error or (not src_path):
            safe_print(r'''Failed to locate %(dhcp_py)s on %(node)s,
                       output = %(src_path)s, error = %(error)s\n''' %
                       {'dhcp_py': dhcp_py,
                        'node': controller_node.hostname,
                        'src_path': src_path,
                        'error': error})
            return
        replace = r'''
            LOG.debug(_('Before sorting dhcp agent subnets: %s'),
                      active_dhcp_agents)
            count_dict = {}
            agent_dict = {}
            for dhcp_agent in active_dhcp_agents:
                agent_dict[dhcp_agent.id] = dhcp_agent
                networks = plugin.list_networks_on_dhcp_agent(
                    context, dhcp_agent.id)
                subnets = networks['networks']
                count = count_dict.get(dhcp_agent.id)
                if not count:
                    count = 0
                count = count + len(subnets)
                count_dict[dhcp_agent.id] = count
            sorted_count_dict = OrderedDict(sorted(count_dict.items(),
                                            key=lambda x: x[1]))
            active_dhcp_agents = []
            for id, count in sorted_count_dict.items():
                if count < 400:
                    active_dhcp_agents.append(agent_dict[id])
            LOG.debug(_('After sorting dhcp agent subnets: %s'),
                      active_dhcp_agents)
            chosen_agents = active_dhcp_agents[:n_agents]
            LOG.debug(_('Chose dhcp agents: %s'),
                      chosen_agents)
'''
        src_dir = os.path.dirname(src_path)
        for node in controller_nodes:
            node.set_dhcp_agent_scheduler_dir(src_dir)
        safe_print("%s is at %s on %s\n" %
                   (dhcp_py, src_dir, controller_node.hostname))
        safe_print(
            "Copy %(dhcp_py)s from openstack controller %(controller_node)s\n"
            % {'controller_node': controller_node.fqdn,
               'dhcp_py': dhcp_py})
        Helper.copy_file_from_remote(controller_node, src_dir, dhcp_py,
                                     controller_node.setup_node_dir)

        dhcp_file_new = open(
            "%s/%s.new" % (controller_node.setup_node_dir, dhcp_py), 'w')
        dhcp_file = open(
            "%s/%s" % (controller_node.setup_node_dir, dhcp_py), 'r')
        for line in dhcp_file:
            if line.startswith("import random"):
                dhcp_file_new.write("import random\n")
                dhcp_file_new.write("from collections import OrderedDict\n")
            elif line.startswith(
                "            chosen_agents = random.sample("
                "active_dhcp_agents, n_agents)"):
                dhcp_file_new.write(replace)
            elif line.startswith("from collections import OrderedDict"):
                pass
            else:
                dhcp_file_new.write(line)
        dhcp_file.close()
        dhcp_file_new.close()
        Helper.run_command_on_local_without_timeout(
            r'''mv %(setup_node_dir)s/%(dhcp_py)s.new %(setup_node_dir)s'''
            '''/%(dhcp_py)s''' %
            {'setup_node_dir': controller_node.setup_node_dir,
             'dhcp_py': dhcp_py})

    @staticmethod
    def prepare_keystone_client(controller_nodes):
        keystone_auth_url = None
        keystone_auth_user = None
        keystone_password = None
        keystone_auth_tenant = None
        if len(controller_nodes) and controller_nodes[0]:
            controller_node = controller_nodes[0]
            safe_print(
                "Copy api-paste.ini from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron', 'api-paste.ini',
                controller_node.setup_node_dir)
            api_paste_conf = open(
                "%s/api-paste.ini" % controller_node.setup_node_dir, 'r')
            for line in api_paste_conf:
                if line.startswith("auth_uri"):
                    keystone_auth_url = line.split("=")[1].strip().split("/v2.0")[0]
                if line.startswith("admin_user"):
                    keystone_auth_user = line.split("=")[1].strip()
                if line.startswith("admin_password"):
                    keystone_password = line.split("=")[1].strip()
                if line.startswith("admin_tenant_name"):
                    keystone_auth_tenant = line.split("=")[1].strip()
        if not keystone_auth_url:
            return
        for controller_node in controller_nodes:
            controller_node.set_keystone_auth_url(keystone_auth_url)
            controller_node.set_keystone_auth_user(keystone_auth_user)
            controller_node.set_keystone_password(keystone_password)
            controller_node.set_keystone_auth_tenant(keystone_auth_tenant)

    @staticmethod
    def check_if_vlan_is_used(controller_nodes):
        if len(controller_nodes) and controller_nodes[0]:
            controller_node = controller_nodes[0]
            safe_print(
                "Copy ml2_conf.ini from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron/plugins/ml2', 'ml2_conf.ini',
                controller_node.setup_node_dir)
            if not controller_node.fuel_cluster_id:
                # always return true for non-fuel environments
                return True
            ml2_conf = open(
                "%s/ml2_conf.ini" % controller_node.setup_node_dir, 'r')
            for line in ml2_conf:
                if line.startswith("tenant_network_types"):
                    tenant_network_types = line.split("=")[1].strip()
                    if 'vlan' in tenant_network_types:
                        return True
                    break
            return False
        # always return true if no controller is specified
        return True

    @staticmethod
    def copy_neutron_config_from_controllers(controller_nodes):
        if len(controller_nodes) and controller_nodes[0]:
            controller_node = controller_nodes[0]
            safe_print(
                "Copy dhcp_agent.ini from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron', 'dhcp_agent.ini',
                controller_node.setup_node_dir)
            safe_print(
                "Copy metadata_agent.ini from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron', 'metadata_agent.ini',
                controller_node.setup_node_dir)
            safe_print(
                "Copy l3_agent.ini from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron', 'l3_agent.ini',
                controller_node.setup_node_dir)

        rabbit_hosts = set()
        rabbit_port = None
        for controller_node in controller_nodes:
            safe_print(
                "Copy neutron.conf from openstack controller "
                "%(controller_node)s\n" %
                {'controller_node': controller_node.fqdn})
            Helper.copy_file_from_remote(
                controller_node, '/etc/neutron', 'neutron.conf',
                controller_node.setup_node_dir)
            # put all controllers to rabbit hosts
            neutron_conf = open(
                "%s/neutron.conf" % controller_node.setup_node_dir, 'r')
            for line in neutron_conf:
                if line.startswith("rabbit_hosts"):
                    hosts_str = line.split("=")[1].strip()
                    hosts = hosts_str.split(',')
                    for host in hosts:
                        if "127.0" in host:
                            rabbit_port = host.split(':')[1]
                            continue
                        rabbit_hosts.add(host.strip())
                    break

        if len(controller_nodes):
            controller_node = controller_nodes[0]
            rabbit_hosts_str = None
            if len(rabbit_hosts):
                rabbit_hosts_str = ','.join(rabbit_hosts)
            else:
                for bridge in controller_node.bridges:
                    if bridge.br_key == 'management':
                        rabbit_ip = bridge.br_ip.split('/')[0]
                        rabbit_hosts_str = "%s:%s" % (rabbit_ip, rabbit_port)
                        break
            for controller_node in controller_nodes:
                controller_node.set_rabbit_hosts(rabbit_hosts_str)
            neutron_conf_new = open(
                "%s/neutron.conf.new" % controller_node.setup_node_dir, 'w')
            neutron_conf = open(
                "%s/neutron.conf" % controller_node.setup_node_dir, 'r')
            for line in neutron_conf:
                if line.startswith("rabbit_hosts"):
                    neutron_conf_new.write(
                        "rabbit_hosts=%s\n" % rabbit_hosts_str)
                else:
                    neutron_conf_new.write(line)
            neutron_conf.close()
            neutron_conf_new.close()
            Helper.run_command_on_local_without_timeout(
                r'''mv %(setup_node_dir)s/neutron.conf.new '''
                '''%(setup_node_dir)s/neutron.conf''' %
                {'setup_node_dir': controller_node.setup_node_dir})

    @staticmethod
    def copy_pkg_scripts_to_remote(node):

        # copy neutron, metadata, dhcp config to node
        if node.install_bsnstacklib:
            safe_print("Copy neutron.conf to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                r'''%(dir)s/neutron.conf''' % {'dir': node.setup_node_dir},
                '/etc/neutron', 'neutron.conf', mode=644)
        if node.deploy_dhcp_agent:
            safe_print("Copy dhcp_agent.ini to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                r'''%(dir)s/dhcp_agent.ini''' % {'dir': node.setup_node_dir},
                '/etc/neutron', 'dhcp_agent.ini', mode=644)
            safe_print("Copy metadata_agent.ini to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                r'''%(dir)s/metadata_agent.ini'''
                % {'dir': node.setup_node_dir},
                '/etc/neutron', 'metadata_agent.ini', mode=644)
        if node.deploy_l3_agent:
            safe_print("Copy l3_agent.ini to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node, r'''%(dir)s/l3_agent.ini'''
                % {'dir': node.setup_node_dir},
                '/etc/neutron', 'l3_agent.ini', mode=644)

        # copy ivs to node
        if (node.deploy_mode == const.T6 and
                node.role == const.ROLE_COMPUTE and node.install_ivs):
            safe_print("Copy %(ivs_pkg)s to %(hostname)s\n" %
                       {'ivs_pkg': node.ivs_pkg, 'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                (r'''%(src_dir)s/%(ivs_pkg)s''' %
                 {'src_dir': node.setup_node_dir,
                  'ivs_pkg': node.ivs_pkg}),
                node.dst_dir, node.ivs_pkg)
            if node.ivs_debug_pkg is not None:
                safe_print("Copy %(ivs_debug_pkg)s to %(hostname)s\n" %
                           {'ivs_debug_pkg': node.ivs_debug_pkg,
                            'hostname': node.fqdn})
                Helper.copy_file_to_remote(
                    node,
                    (r'''%(src_dir)s/%(ivs_debug_pkg)s''' %
                     {'src_dir': node.setup_node_dir,
                      'ivs_debug_pkg': node.ivs_debug_pkg}),
                    node.dst_dir, node.ivs_debug_pkg)

        if (node.role == const.ROLE_CEPH or
                const.ROLE_CINDER in node.role.lower() or
                node.role == const.ROLE_MONGO or
                node.deploy_mode == const.T5):
            # copy send_lldp to t5 compute nodes
            safe_print("Copy send_lldp to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node,
                r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                '''%(python_template_dir)s/send_lldp''' %
                {'setup_node_dir': node.setup_node_dir,
                 'deploy_mode': node.deploy_mode,
                 'python_template_dir': const.PYTHON_TEMPLATE_DIR},
                node.dst_dir, 'send_lldp')

        # we don't support router rule grid in kilo t6. hind it.
        if (node.openstack_release == const.OS_RELEASE_KILO or
                node.openstack_release == const.OS_RELEASE_KILO_V2):
            if (node.deploy_mode == const.T6 and
                    node.role == const.ROLE_NEUTRON_SERVER):
                safe_print("Copy project_tabs.py to %(hostname)s\n" %
                       {'hostname': node.fqdn})
                Helper.copy_file_to_remote(
                    node,
                    r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                    '''%(python_template_dir)s/project_tabs.py''' %
                    {'setup_node_dir': node.setup_node_dir,
                     'deploy_mode': node.deploy_mode,
                     'python_template_dir': const.PYTHON_TEMPLATE_DIR},
                    '/usr/share/openstack-dashboard/openstack_dashboard/dashboards/project/routers',
                    'tabs.py')
                safe_print("Copy admin_tabs.py to %(hostname)s\n" %
                       {'hostname': node.fqdn})
                Helper.copy_file_to_remote(
                    node,
                    r'''%(setup_node_dir)s/%(deploy_mode)s/'''
                    '''%(python_template_dir)s/admin_tabs.py''' %
                    {'setup_node_dir': node.setup_node_dir,
                     'deploy_mode': node.deploy_mode,
                     'python_template_dir': const.PYTHON_TEMPLATE_DIR},
                    '/usr/share/openstack-dashboard/openstack_dashboard/dashboards/admin/routers',
                    'tabs.py')

        # copy bash script to node
        safe_print("Copy bash script to %(hostname)s\n" %
                   {'hostname': node.fqdn})
        Helper.copy_file_to_remote(
            node, node.bash_script_path, node.dst_dir,
            "%(hostname)s.sh" % {'hostname': node.hostname})

        # copy puppet script to node
        safe_print("Copy puppet script to %(hostname)s\n" %
                   {'hostname': node.fqdn})
        Helper.copy_file_to_remote(node,
           node.puppet_script_path,
           node.dst_dir,
           "%(hostname)s.pp" % {'hostname': node.hostname})

        # copy selinux script to node
        if node.os in const.RPM_OS_SET:
            safe_print("Copy bsn selinux policy to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(node,
               node.selinux_script_path,
               node.dst_dir,
               "%(hostname)s.te" % {'hostname': node.hostname})

        if node.role == const.ROLE_NEUTRON_SERVER:
            # copy ospurge script to node
            safe_print("Copy ospurge script to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node, node.ospurge_script_path, node.dst_dir,
                "%(hostname)s_ospurge.sh" % {'hostname': node.hostname})

            # copy dhcp reschedule script to node
            safe_print("Copy dhcp reschedule script to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_file_to_remote(
                node, node.dhcp_reschedule_script_path, node.dst_dir,
                'dhcp_reschedule.sh')

            # patch dhcp scheduler for juno
            if node.openstack_release == 'juno':
                safe_print(
                    "Copy dhcp_agent_scheduler.py to %(hostname)s\n" %
                    {'hostname': node.fqdn})
                Helper.copy_file_to_remote(
                    node,
                    "%s/dhcp_agent_scheduler.py" % node.setup_node_dir,
                    node.dhcp_agent_scheduler_dir, 'dhcp_agent_scheduler.py')

            # copy horizon patch to node
            if node.deploy_horizon_patch:
                safe_print("Copy horizon patch to %(hostname)s\n" %
                           {'hostname': node.fqdn})
                Helper.copy_file_to_remote(
                    node,
                    (r'''%(src_dir)s/%(horizon_patch)s''' %
                     {'src_dir': node.setup_node_dir,
                      'horizon_patch': node.horizon_patch}),
                    node.dst_dir, node.horizon_patch)

        # copy rootwrap to remote
        if node.fuel_cluster_id:
            safe_print("Copy rootwrap to %(hostname)s\n" %
                       {'hostname': node.fqdn})
            Helper.copy_dir_to_remote(
                node,
                (r'''%(src_dir)s/rootwrap''' %
                 {'src_dir': node.setup_node_dir}),
                node.dst_dir)

    @staticmethod
    def check_os_service_status(node, service_name_in):
        # run service status command and return :-) or :-(
        output = Helper.run_command_on_remote(
            node, r'''sudo bash service %(service_name)s status''' %
            {'service_name': service_name_in})
        if "running" in output:
            return ":-)"
        else:
            return ":-("

    @staticmethod
    def check_ivs_version(node):
        # required version is node.ivs_version
        output = Helper.run_command_on_remote(node, r'''ivs --version''')
        # version string looks like this:
        # ivs 3.0.0 (2015-08-14.18:26-39a875b trusty-amd64)
        split_version = string.split(output, ' ')
        # split_version[1] would be empty in error scenario
        if node.ivs_version == split_version[1]:
            return ':-)'
        else:
            return (':-( Expected ' + node.ivs_version +
                    ' Actual ' + split_version[1])

    @staticmethod
    def certify_node(node):
        if not node.certificate_dir:
            safe_print("Node %(fqdn)s does not have certificate directory.\n"
                       % {'fqdn' : node.fqdn})
            return
        if not node.mac:
            safe_print("Node %s does not have mac.\n" % node.fqdn)
            return
        mac = node.mac.replace(":", "-")
        macs = [mac.upper(), mac.lower()]
        for mac in macs:
            cacert = ("%s/ca.cert" % node.certificate_dir)
            cert = ("%(dir)s/%(mac)s.switch.cluster.pem" %
                   {'dir': node.certificate_dir,
                    'mac': mac})
            key = ("%(dir)s/%(mac)s.switch.cluster.key" %
                  {'dir': const.KEY_DIR,
                   'mac': mac})
            csr = ("%(dir)s/%(mac)s.switch.cluster.csr" %
                  {'dir': const.CSR_DIR,
                   'mac': mac})

            # copy ca.cert, key pairs, certificate to /etc/ivs/
            if os.path.isfile(cacert):
                safe_print("Copy %(f)s to %(fqdn)s\n" %
                          {'fqdn' : node.fqdn,
                           'f' : cacert})
                Helper.copy_file_to_remote(node,
                    src_file=cacert,
                    dst_dir="/etc/ivs",
                    dst_file="ca.cert",
                    mode=644)

            if os.path.isfile(cert):
                safe_print("Copy %(f)s to %(fqdn)s\n" %
                          {'fqdn' : node.fqdn,
                           'f' : cert})
                Helper.copy_file_to_remote(node,
                    src_file=cert,
                    dst_dir="/etc/ivs",
                    dst_file="ivs.cert",
                    mode=644)

            if os.path.isfile(key):
                safe_print("Copy %(f)s to %(fqdn)s\n" %
                          {'fqdn' : node.fqdn,
                           'f' : key})
                Helper.copy_file_to_remote(node,
                    src_file=key,
                    dst_dir="/etc/ivs",
                    dst_file="ivs.key",
                    mode=644)

            if os.path.isfile(csr):
                safe_print("Copy %(f)s to %(fqdn)s\n" %
                          {'fqdn' : node.fqdn,
                           'f' : csr})
                Helper.copy_file_to_remote(node,
                    src_file=csr,
                    dst_dir="/etc/ivs",
                    dst_file=("%s.switch.cluster.csr" % mac),
                    mode=644)

            safe_print("Restart ivs on %s.\n" % node.fqdn)
            Helper.run_command_on_remote(node, "service ivs restart")

    @staticmethod
    def generate_csr(node):
        if not node.mac:
            safe_print("Node %s does not have mac.\n" % node.fqdn)
            return
        mac = node.mac.lower().replace(':', '-')
        cn = "%s.switch.cluster" % mac
        csr_sub = const.CSR_SUB % {'cn': cn}
        key_name = "%s.switch.cluster.key" % mac
        csr_name = "%s.switch.cluster.csr" % mac

        key_cmd = ("sudo openssl genrsa -out %(dir)s/%(key_name)s 2048" %
                  {"dir" : const.KEY_DIR,
                   "key_name" : key_name})
        subprocess.call(key_cmd, shell=True)

        csr_cmd = ("sudo openssl req -new -key %(key_dir)s/%(key_name)s "
                   "-out %(csr_dir)s/%(csr_name)s -subj \"%(sub)s\"" %
                  {'key_dir': const.KEY_DIR, 'key_name' : key_name,
                   'csr_dir': const.CSR_DIR, 'csr_name' : csr_name,
                   'sub': csr_sub})
        subprocess.call(csr_cmd, shell=True)

    @staticmethod
    def support_node(node):
        if not Helper.is_connected(node):
            safe_print("Cannot access node %s.\n" % node.fqdn)
            return
        cmd = "mkdir -p ~/%s/log" % node.fqdn
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "mkdir -p ~/%s/config" % node.fqdn
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "pip show bsnstacklib > ~/%s/log/version" % node.fqdn
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /etc/neutron/* ~/%s/config/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /var/log/upstart ~/%s/log/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /var/crash ~/%s/log/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /var/log/neutron/* ~/%s/log/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /var/log/nova/* ~/%s/log/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "cp -r /var/log/heat/* ~/%s/log/" % node.fqdn
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=10)

        cmd = "tar -czf %(fqdn)s.tar.gz %(fqdn)s" % {'fqdn': node.fqdn}
        safe_print("Run \"%(cmd)s\" on node %(fqdn)s\n" %
                  {"cmd": cmd, "fqdn": node.fqdn})
        Helper.run_command_on_remote(node, cmd, timeout=20)

        Helper.copy_file_from_remote(node,
            src_dir="~",
            src_file=("%s.tar.gz" % node.fqdn),
            dst_dir=const.SUPPORT_DIR)

    @staticmethod
    def is_connected(node):
        '''check if installer can ssh to a node'''
        ret = Helper.run_command_on_local_without_timeout("ping %s -c1" % node.hostname)
        if "0 received" in str(ret):
            safe_print("Cannot ping node %s\n" % node.fqdn)
            return False
        ret = Helper.run_command_on_remote_without_timeout(node, "pwd")
        if "not" in str(ret):
            safe_print("Cannot ssh node %s\n" % node.fqdn)
            return False
        return True
