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

rhosp_automate_register=%(rhosp_automate_register)s
rhosp_register_username=%(rhosp_register_username)s
rhosp_register_passwd=%(rhosp_register_passwd)s


controller() {
    echo "Stop and disable metadata agent, dhcp agent, l3 agent"
    sudo pcs resource disable neutron-metadata-agent-clone
    sudo pcs resource disable neutron-metadata-agent
    sudo pcs resource cleanup neutron-metadata-agent-clone
    sudo pcs resource cleanup neutron-metadata-agent
    sudo pcs resource delete neutron-metadata-agent-clone
    sudo pcs resource delete neutron-metadata-agent

    sudo pcs resource disable neutron-dhcp-agent-clone
    sudo pcs resource disable neutron-dhcp-agent
    sudo pcs resource cleanup neutron-dhcp-agent-clone
    sudo pcs resource cleanup neutron-dhcp-agent
    sudo pcs resource delete neutron-dhcp-agent-clone
    sudo pcs resource delete neutron-dhcp-agent

    sudo pcs resource disable neutron-l3-agent-clone
    sudo pcs resource disable neutron-l3-agent
    sudo pcs resource cleanup neutron-l3-agent-clone
    sudo pcs resource cleanup neutron-l3-agent
    sudo pcs resource delete neutron-l3-agent-clone
    sudo pcs resource delete neutron-l3-agent

    # deploy bcf
    sudo puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # bsnstacklib installed and property files updated. now perform live db migration
    echo "Performing live DB migration for Neutron.."
    if [[ $openstack_release == 'kilo' || $openstack_release == 'kilo_v2' ]]; then
        neutron-db-manage --service bsn_service_plugin upgrade head
    else
        neutron-db-manage upgrade heads
    fi

    # restart keystone and httpd
    sudo systemctl daemon-reload
    sudo systemctl restart openstack-keystone
    sudo systemctl restart httpd

    echo "Restart neutron-server"
    sudo rm -rf /var/lib/neutron/host_certs/*
    sudo systemctl restart neutron-server
}

compute() {

    # copy send_lldp to /bin
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp

    # update configure files and services
    sudo puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp
    sudo systemctl daemon-reload

    # remove bond from ovs
    sudo ovs-appctl bond/list | grep -v slaves | grep %(bond)s
    if [[ $? == 0 ]]; then
        sudo ovs-vsctl --if-exists del-port %(bond)s
        declare -a uplinks=(%(uplinks)s)
        len=${#uplinks[@]}
        for (( i=0; i<$len; i++ )); do
            sudo ovs-vsctl --if-exists del-port ${uplinks[$i]}
        done
    fi

    # flip uplinks and bond
    declare -a uplinks=(%(uplinks)s)
    len=${#uplinks[@]}
    sudo ifdown %(bond)s
    for (( i=0; i<$len; i++ )); do
        sudo ifdown ${uplinks[$i]}
    done
    for (( i=0; i<$len; i++ )); do
        sudo ifup ${uplinks[$i]}
    done
    sudo ifup %(bond)s

    # add bond to ovs
    sudo ovs-vsctl --may-exist add-port %(br_bond)s %(bond)s
    sleep 10
    sudo systemctl restart send_lldp

    # assign default gw
    sudo bash /etc/rc.d/rc.local

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent, neutron-dhcp-agent'
        sudo systemctl enable neutron-metadata-agent
        sudo systemctl restart neutron-metadata-agent
        sudo systemctl enable neutron-dhcp-agent
        sudo systemctl restart neutron-dhcp-agent
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo 'Restart neutron-l3-agent, neutron-metadata-agent'
        sudo systemctl enable neutron-metadata-agent
        sudo systemctl restart neutron-metadata-agent
        sudo systemctl enable neutron-l3-agent
        sudo systemctl restart neutron-l3-agent
        sudo systemctl stop openstack-nova-compute
        sudo systemctl disable openstack-nova-compute
    fi
}


set +e

# update dns
sudo sed -i "s/^nameserver.*/nameserver %(rhosp_undercloud_dns)s/" /etc/resolv.conf

# assign default gw
sudo ip route del default
sudo ip route del default
sudo ip route add default via $default_gw

# auto register
if [[ $rhosp_automate_register == true ]]; then
    sudo subscription-manager register --username $rhosp_register_username --password $rhosp_register_passwd --auto-attach
fi

sudo subscription-manager version | grep Unknown
if [[ $? == 0 ]]; then
    echo "node is not registered in subscription-manager"
    exit 1
fi

# prepare dependencies
wget -r --no-parent --no-directories --timestamping --accept 'epel-release-7-*.rpm' 'http://dl.fedoraproject.org/pub/epel/7/x86_64/e/'
rpm -iUvh epel-release-7-*.rpm
sudo rpm -ivh https://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-10.noarch.rpm
sudo yum update -y
sudo yum groupinstall -y 'Development Tools'
sudo yum install -y python-devel puppet python-pip wget libffi-devel openssl-devel ntp
sudo easy_install pip
sudo puppet module install --force puppetlabs-inifile
sudo puppet module install --force puppetlabs-stdlib

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    pip uninstall -y bsnstacklib
    sudo pip install --upgrade "bsnstacklib>%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
fi
sudo systemctl stop neutron-bsn-agent
sudo systemctl disable neutron-bsn-agent

if [[ $is_controller == true ]]; then
    controller
else
    compute
fi

set -e

exit 0

