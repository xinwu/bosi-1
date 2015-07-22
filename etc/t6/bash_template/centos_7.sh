#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
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

    echo 'Restart neutron-server'
    rm -rf /etc/neutron/plugins/ml2/host_certs/*
    systemctl restart neutron-server

    # schedule cron job to reschedule network in case dhcp agent fails
    chmod a+x /bin/dhcp_reschedule.sh
    crontab -r
    (crontab -l; echo "*/30 * * * * /bin/dhcp_reschedule.sh") | crontab -
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

    # install ivs
    if [[ $install_ivs == true ]]; then
        # check ivs version compatability
        pass=true
        ivs --version
        if [[ $? == 0 ]]; then
            old_version=$(ivs --version | awk '{print $2}')
            old_version_numbers=(${old_version//./ })
            new_version_numbers=(${ivs_version//./ })
            if [[ "$old_version" != "${old_version%%$ivs_version*}" ]]; then
                pass=true
            elif [[ $old_version > $ivs_version ]]; then
                pass=false
            elif [[ $((${new_version_numbers[0]}-1)) -gt ${old_version_numbers[0]} ]]; then
                pass=false
            fi
        fi

        if [[ $pass == true ]]; then
            rpm -ivh --force %(dst_dir)s/%(ivs_pkg)s
            if [[ -f %(dst_dir)s/%(ivs_debug_pkg)s ]]; then
                rpm -ivh --force %(dst_dir)s/%(ivs_debug_pkg)s
            fi
        else
            echo "ivs upgrade fails version validation"
        fi
    fi

    if [[ $deploy_haproxy == true ]]; then
        groupadd nogroup
        yum install -y keepalived haproxy
        sysctl -w net.ipv4.ip_nonlocal_bind=1
    fi

    # full installation
    if [[ $install_all == true ]]; then
        cp /usr/lib/systemd/system/neutron-openvswitch-agent.service /usr/lib/systemd/system/neutron-bsn-agent.service

        # stop ovs agent, otherwise, ovs bridges cannot be removed
        systemctl stop neutron-openvswitch-agent
        systemctl disable neutron-openvswitch-agent

        # remove ovs, example ("br-storage" "br-prv" "br-ex")
        declare -a ovs_br=(%(ovs_br)s)
        len=${#ovs_br[@]}
        for (( i=0; i<$len; i++ )); do
            ovs-vsctl del-br ${ovs_br[$i]}
            brctl delbr ${ovs_br[$i]}
            ip link del dev ${ovs_br[$i]}
        done

        # delete ovs br-int
        while true; do
            systemctl stop neutron-openvswitch-agent
            systemctl disable neutron-openvswitch-agent
            ovs-vsctl del-br %(br-int)s
            ip link del dev %(br-int)s
            sleep 1
            ovs-vsctl show | grep %(br-int)s
            if [[ $? != 0 ]]; then
                break
            fi
        done

        #bring down all bonds
        declare -a bonds=(%(bonds)s)
        len=${#bonds[@]}
        for (( i=0; i<$len; i++ )); do
            ip link del dev ${bonds[$i]}
        done

        # deploy bcf
        puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

        #reset uplinks to move them out of bond
        declare -a uplinks=(%(uplinks)s)
        len=${#uplinks[@]}
        for (( i=0; i<$len; i++ )); do
            ip link set ${uplinks[$i]} down
        done
        sleep 2
        for (( i=0; i<$len; i++ )); do
            ip link set ${uplinks[$i]} up
        done

        # assign default gw
        bash /etc/rc.d/rc.local

    fi

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        systemctl restart neutron-metadata-agent
        systemctl enable neutron-metadata-agent
        systemctl restart neutron-dhcp-agent
        systemctl enable neutron-dhcp-agent
    fi

    # restart libvirtd and nova compute on compute node
    echo 'Restart libvirtd and openstack-nova-compute'
    systemctl restart libvirtd
    systemctl enable libvirtd
    systemctl restart openstack-nova-compute
    systemctl enable openstack-nova-compute

    # restart bsn-agent
    systemctl restart neutron-bsn-agent
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

set -e

