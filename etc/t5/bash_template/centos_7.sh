#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
deploy_l3_agent=%(deploy_l3_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
deploy_horizon_patch=%(deploy_horizon_patch)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
deploy_haproxy=%(deploy_haproxy)s


controller() {

    echo 'Stop and disable metadata agent, dhcp agent, l3 agent'
    systemctl stop neutron-l3-agent
    systemctl disable neutron-l3-agent
    systemctl stop neutron-dhcp-agent
    systemctl disable neutron-dhcp-agent
    systemctl stop neutron-metadata-agent
    systemctl disable neutron-metadata-agent
    systemctl stop neutron-bsn-agent
    systemctl disable neutron-bsn-agent

    # copy dhcp_reschedule.sh to /bin
    cp %(dst_dir)s/dhcp_reschedule.sh /bin/
    chmod 777 /bin/dhcp_reschedule.sh

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # deploy bcf horizon patch to controller node
    if [[ $deploy_horizon_patch == true ]]; then
        # enable lb
        sed -i 's/'"'"'enable_lb'"'"': False/'"'"'enable_lb'"'"': True/g' %(horizon_base_dir)s/openstack_dashboard/local/local_settings.py

        # chmod neutron config since bigswitch horizon patch reads neutron config as well
        chmod -R a+r /usr/share/neutron
        chmod -R a+x /usr/share/neutron
        chmod -R a+r /etc/neutron
        chmod -R a+x /etc/neutron

        if [[ -f %(dst_dir)s/%(horizon_patch)s ]]; then
            chmod -R 777 '/etc/neutron/'
            tar -xzf %(dst_dir)s/%(horizon_patch)s -C %(dst_dir)s
            fs=('openstack_dashboard/dashboards/admin/dashboard.py' 'openstack_dashboard/dashboards/project/dashboard.py' 'openstack_dashboard/dashboards/admin/connections' 'openstack_dashboard/dashboards/project/connections' 'openstack_dashboard/dashboards/project/routers/extensions/routerrules/rulemanager.py' 'openstack_dashboard/dashboards/project/routers/extensions/routerrules/tabs.py')
            for f in "${fs[@]}"
            do
                if [[ -f %(dst_dir)s/%(horizon_patch_dir)s/$f ]]; then
                    yes | cp -rfp %(dst_dir)s/%(horizon_patch_dir)s/$f %(horizon_base_dir)s/$f
                else
                    mkdir -p %(horizon_base_dir)s/$f
                    yes | cp -rfp %(dst_dir)s/%(horizon_patch_dir)s/$f/* %(horizon_base_dir)s/$f
                fi
            done
            find "%(horizon_base_dir)s" -name "*.pyc" | xargs rm
            find "%(horizon_base_dir)s" -name "*.pyo" | xargs rm
            systemctl restart httpd
        fi
    fi

    # restart keystone and horizon
    systemctl restart httpd

    # schedule cron job to reschedule network in case dhcp agent fails
    chmod a+x /bin/dhcp_reschedule.sh
    crontab -r
    (crontab -l; echo "*/30 * * * * /bin/dhcp_reschedule.sh") | crontab -

    echo 'Restart neutron-server'
    rm -rf /etc/neutron/plugins/ml2/host_certs/*
    systemctl restart neutron-server
}

compute() {
    # TODO update bond mode to balance-xor

    # copy send_lldp to /bin
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp

    # Install dhcp, metadata and l3 agent
    yum install -y neutron-metadata-agent
    yum install -y neutron-dhcp-agent
    yum install -y neutron-l3-agent
    # Stop all agents by default
    systemctl stop neutron-l3-agent
    systemctl disable neutron-l3-agent
    systemctl stop neutron-dhcp-agent
    systemctl disable neutron-dhcp-agent
    systemctl stop neutron-metadata-agent
    systemctl disable neutron-metadata-agent

    # patch linux/dhcp.py to make sure static host route is pushed to instances
    dhcp_py=$(find /usr -name dhcp.py | grep linux)
    dhcp_dir=$(dirname "${dhcp_py}")
    sed -i 's/if (isolated_subnets\[subnet.id\] and/if (True and/g' $dhcp_py
    find $dhcp_dir -name "*.pyc" | xargs rm
    find $dhcp_dir -name "*.pyo" | xargs rm

    if [[ $deploy_haproxy == true ]]; then
        groupadd nogroup
        yum install -y keepalived haproxy
        sysctl -w net.ipv4.ip_nonlocal_bind=1
    fi

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        systemctl restart neutron-metadata-agent
        systemctl enable neutron-metadata-agent
        systemctl restart neutron-dhcp-agent
        systemctl enable neutron-dhcp-agent
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo "Restart neutron-l3-agent"
        systemctl restart neutron-l3-agent
        systemctl enable neutron-l3-agent
    fi

    # we install this before puppet so the conf files are present and restart after puppet
    # so that changes made by puppet are reflected correctly
    if [[ $deploy_haproxy == true ]]; then
        echo "Restart neutron-lbaas-agent"
        systemctl restart neutron-lbaas-agent
    fi

    # restart libvirtd and nova compute on compute node
    echo 'Restart libvirtd, openstack-nova-compute and neutron-bsn-agent'
    systemctl restart libvirtd
    systemctl enable libvirtd
    systemctl restart openstack-nova-compute
    systemctl enable openstack-nova-compute
}


set +e

# Make sure only root can run this script
if [ "$(id -u)" != "0" ]; then
   echo -e "Please run as root" 
   exit 1
fi

# prepare dependencies
rpm -iUvh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
rpm -ivh https://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-10.noarch.rpm
# point to the correct openstack distro when installing packages
yum install http://rdo.fedorapeople.org/openstack-juno/rdo-release-juno.rpm
yum groupinstall -y 'Development Tools'
yum install -y python-devel puppet python-pip wget libffi-devel openssl-devel
yum update -y
easy_install pip
puppet module install --force puppetlabs-inifile
puppet module install --force puppetlabs-stdlib
puppet module install jfryman-selinux
#mkdir -p /etc/puppet/modules/selinux/files
#cp %(dst_dir)s/%(hostname)s.te /etc/puppet/modules/selinux/files/centos.te

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    pip install --upgrade "bsnstacklib<%(bsnstacklib_version)s"
fi

if [[ $is_controller == true ]]; then
    controller
else
    compute
fi

# patch nova rootwrap for fuel
if [[ ${fuel_cluster_id} != 'None' ]]; then
    mkdir -p /usr/share/nova
    rm -rf /usr/share/nova/rootwrap
    rm -rf %(dst_dir)s/rootwrap/rootwrap
    cp -r %(dst_dir)s/rootwrap /usr/share/nova/
    chmod -R 777 /usr/share/nova/rootwrap
    rm -rf /usr/share/nova/rootwrap/rootwrap
fi

set -e

exit 0

























#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
deploy_l3_agent=%(deploy_l3_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
deploy_horizon_patch=%(deploy_horizon_patch)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
deploy_haproxy=%(deploy_haproxy)s
default_gw=%(default_gw)s


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

    # copy dhcp_reschedule.sh to /bin
    cp %(dst_dir)s/dhcp_reschedule.sh /bin/
    chmod 777 /bin/dhcp_reschedule.sh

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # deploy bcf horizon patch to controller node
    if [[ $deploy_horizon_patch == true ]]; then
        # enable lb
        sed -i 's/'"'"'enable_lb'"'"': False/'"'"'enable_lb'"'"': True/g' %(horizon_base_dir)s/openstack_dashboard/local/local_settings.py

        # chmod neutron config since bigswitch horizon patch reads neutron config as well
        chmod -R a+r /usr/share/neutron
        chmod -R a+x /usr/share/neutron
        chmod -R a+r /etc/neutron
        chmod -R a+x /etc/neutron

        if [[ -f %(dst_dir)s/%(horizon_patch)s ]]; then
            chmod -R 777 '/etc/neutron/'
            tar -xzf %(dst_dir)s/%(horizon_patch)s -C %(dst_dir)s
            fs=('openstack_dashboard/dashboards/admin/dashboard.py' 'openstack_dashboard/dashboards/project/dashboard.py' 'openstack_dashboard/dashboards/admin/connections' 'openstack_dashboard/dashboards/project/connections' 'openstack_dashboard/dashboards/project/routers/extensions/routerrules/rulemanager.py' 'openstack_dashboard/dashboards/project/routers/extensions/routerrules/tabs.py')
            for f in "${fs[@]}"
            do
                if [[ -f %(dst_dir)s/%(horizon_patch_dir)s/$f ]]; then
                    yes | cp -rfp %(dst_dir)s/%(horizon_patch_dir)s/$f %(horizon_base_dir)s/$f
                else
                    mkdir -p %(horizon_base_dir)s/$f
                    yes | cp -rfp %(dst_dir)s/%(horizon_patch_dir)s/$f/* %(horizon_base_dir)s/$f
                fi
            done
            find "%(horizon_base_dir)s" -name "*.pyc" | xargs rm
            find "%(horizon_base_dir)s" -name "*.pyo" | xargs rm
            systemctl restart httpd
        fi
    fi

    # restart keystone and httpd
    systemctl restart httpd

    echo "Restart neutron-server"
    rm -rf /var/lib/neutron/host_certs/*
    systemctl restart neutron-server
}

compute() {

    systemctl stop neutron-l3-agent
    systemctl disable neutron-l3-agent
    systemctl stop neutron-dhcp-agent
    systemctl disable neutron-dhcp-agent
    systemctl stop neutron-metadata-agent
    systemctl disable neutron-metadata-agent

    # patch linux/dhcp.py to make sure static host route is pushed to instances
    dhcp_py=$(find /usr -name dhcp.py | grep linux)
    dhcp_dir=$(dirname "${dhcp_py}")
    sed -i 's/if (isolated_subnets\[subnet.id\] and/if (True and/g' $dhcp_py
    find $dhcp_dir -name "*.pyc" | xargs rm
    find $dhcp_dir -name "*.pyo" | xargs rm

    if [[ $deploy_haproxy == true ]]; then
        groupadd nogroup
        yum install -y keepalived haproxy
        sysctl -w net.ipv4.ip_nonlocal_bind=1
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

    # add bond to ovs
    ovs-vsctl --may-exist add-port %(br_bond)s %(bond)s
    sleep 5
    systemctl restart send_lldp

    # assign default gw
    bash /etc/rc.d/rc.local

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent, neutron-dhcp-agent and neutron-l3-agent'
        systemctl enable neutron-metadata-agent
        systemctl restart neutron-metadata-agent
        systemctl enable neutron-dhcp-agent
        systemctl restart neutron-dhcp-agent
    fi

    if [[ $deploy_l3_agent == true ]]; then
        systemctl enable neutron-l3-agent
        systemctl restart neutron-l3-agent
    fi

    # restart libvirtd and nova compute on compute node
    echo 'Restart libvirtd, openstack-nova-compute and neutron-bsn-agent'
    systemctl restart libvirtd
    systemctl enable libvirtd
    systemctl restart openstack-nova-compute
    systemctl enable openstack-nova-compute
    systemctl restart neutron-bsn-agent
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
sudo rpm -iUvh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
sudo rpm -ivh https://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-10.noarch.rpm
sudo yum update -y
sudo yum groupinstall -y 'Development Tools'
sudo yum install -y python-devel puppet python-pip wget libffi-devel openssl-devel ntp
sudo easy_install pip
sudo puppet module install --force puppetlabs-inifile
sudo puppet module install --force puppetlabs-stdlib

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    sudo pip install --upgrade "bsnstacklib<%(bsnstacklib_version)s"
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




