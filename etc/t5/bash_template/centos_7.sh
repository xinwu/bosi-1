#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
deploy_l3_agent=%(deploy_l3_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
default_gw=%(default_gw)s
pip_proxy=%(pip_proxy)s


controller() {
    echo "Stop and disable metadata agent, dhcp agent, l3 agent"
    systemctl stop neutron-l3-agent
    systemctl disable neutron-l3-agent
    systemctl stop neutron-dhcp-agent
    systemctl disable neutron-dhcp-agent
    systemctl stop neutron-metadata-agent
    systemctl disable neutron-metadata-agent
    systemctl stop neutron-bsn-agent
    systemctl disable neutron-bsn-agent

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # bsnstacklib installed and property files updated. now perform live db migration
    echo "Performing live DB migration for Neutron.."
    if [[ $openstack_release == 'kilo' || $openstack_release == 'kilo_v2' ]]; then
        neutron-db-manage --service bsn_service_plugin upgrade head
    else
        neutron-db-manage upgrade heads
    fi

    # deploy bcf horizon patch to controller node
    cp /usr/lib/python2.7/site-packages/horizon_bsn/enabled/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/
    systemctl restart httpd

    echo "Restart neutron-server"
    rm -rf /var/lib/neutron/host_certs/*
    systemctl restart neutron-server
}

compute() {

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Stop and disable neutron-metadata-agent and neutron-dhcp-agent'
        systemctl stop neutron-dhcp-agent
        systemctl disable neutron-dhcp-agent
        systemctl stop neutron-metadata-agent
        systemctl disable neutron-metadata-agent
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo 'Stop and disable neutron-l3-agent'
        systemctl stop neutron-l3-agent
        systemctl disable neutron-l3-agent
    fi

    # copy send_lldp to /bin
    cp %(dst_dir)s/send_lldp /bin/
    chmod 777 /bin/send_lldp

    # update configure files and services
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp
    systemctl daemon-reload

    # remove bond from ovs
    ovs-appctl bond/list | grep -v slaves | grep %(bond)s
    if [[ $? == 0 ]]; then
        ovs-vsctl --if-exists del-port %(bond)s
        declare -a uplinks=(%(uplinks)s)
        len=${#uplinks[@]}
        for (( i=0; i<$len; i++ )); do
            ovs-vsctl --if-exists del-port ${uplinks[$i]}
        done
    fi

    # flip uplinks and bond
    declare -a uplinks=(%(uplinks)s)
    len=${#uplinks[@]}
    ifdown %(bond)s
    for (( i=0; i<$len; i++ )); do
        ifdown ${uplinks[$i]}
    done
    for (( i=0; i<$len; i++ )); do
        ifup ${uplinks[$i]}
    done
    ifup %(bond)s

    # add physical interface bridge
    # this may be absent in case of packstack
    ovs-vsctl --may-exist add-br %(br_bond)s
    # add bond to ovs
    ovs-vsctl --may-exist add-port %(br_bond)s %(bond)s
    sleep 10
    systemctl restart send_lldp

    # restart neutron ovs plugin
    # this ensures connections between br-int and br-bond are created fine
    systemctl restart neutron-openvswitch-agent

    # assign default gw
    bash /etc/rc.d/rc.local

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        systemctl enable neutron-metadata-agent
        systemctl restart neutron-metadata-agent
        systemctl enable neutron-dhcp-agent
        systemctl restart neutron-dhcp-agent
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo "Restart neutron-l3-agent"
        systemctl enable neutron-l3-agent
        systemctl restart neutron-l3-agent
    fi
}


set +e

# Make sure only root can run this script
if [ "$(id -u)" != "0" ]; then
   echo -e "Please run as root"
   exit 1
fi

# prepare dependencies
wget -r --no-parent --no-directories --timestamping --accept 'epel-release-7-*.rpm' 'http://dl.fedoraproject.org/pub/epel/7/x86_64/e/'
rpm -iUvh epel-release-7-*.rpm
rpm -ivh https://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-10.noarch.rpm
yum groupinstall -y 'Development Tools'
yum install -y python-devel puppet python-pip wget libffi-devel openssl-devel
easy_install pip
pip install --upgrade funcsigs
puppet module install --force puppetlabs-inifile
puppet module install --force puppetlabs-stdlib

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    sleep 2
    pip uninstall -y bsnstacklib
    sleep 2
    if [[ $pip_proxy == false ]]; then
        pip install --upgrade "bsnstacklib>=%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
        pip install --upgrade "horizon-bsn>=%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
    else
        pip --proxy $pip_proxy  install --upgrade "bsnstacklib>=%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
        pip --proxy $pip_proxy  install --upgrade "horizon-bsn>=%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
    fi
fi

if [[ $is_controller == true ]]; then
    controller
else
    compute
fi

set -e

exit 0
