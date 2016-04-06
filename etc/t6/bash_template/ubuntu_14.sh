#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
bsnstacklib_version="2015.1.53"
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
is_ceph=%(is_ceph)s
is_mongo=%(is_mongo)s
deploy_horizon_patch=%(deploy_horizon_patch)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
skip_ivs_version_check=%(skip_ivs_version_check)s
pip_proxy=%(pip_proxy)s

controller() {

    # copy dhcp_reschedule.sh to /bin
    cp %(dst_dir)s/dhcp_reschedule.sh /bin/
    chmod 777 /bin/dhcp_reschedule.sh

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # bsnstacklib installed and property files updated. now perform live db migration
    echo "Performing live DB migration for Neutron.."
    neutron-db-manage upgrade heads

    echo 'Stop and disable neutron-metadata-agent and neutron-dhcp-agent'
    if [[ ${fuel_cluster_id} != 'None' ]]; then
        crm resource stop p_neutron-dhcp-agent
        crm resource stop p_neutron-metadata-agent
        crm resource stop p_neutron-l3-agent
        sleep 10
        crm resource cleanup p_neutron-dhcp-agent
        crm resource cleanup p_neutron-metadata-agent
        crm resource cleanup p_neutron-l3-agent
        sleep 10
        crm configure delete p_neutron-dhcp-agent
        crm configure delete p_neutron-metadata-agent
        crm configure delete p_neutron-l3-agent
    fi
    service neutron-metadata-agent stop
    rm -f /etc/init/neutron-metadata-agent.conf
    service neutron-dhcp-agent stop
    rm -f /etc/init/neutron-dhcp-agent.conf
    service neutron-l3-agent stop
    rm -f /etc/init/neutron-l3-agent.conf
    service neutron-bsn-agent stop
    rm -f /etc/init/neutron-bsn-agent.conf


    # deploy horizon plugin
    cp /usr/local/lib/python2.7/dist-packages/horizon_bsn/enabled/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/
    #if [[ $deploy_horizon_patch == true ]]; then
        # TODO: new way to plugin horizon
    #fi

    # schedule cron job to reschedule network in case dhcp agent fails
    chmod a+x /bin/dhcp_reschedule.sh
    crontab -r
    (crontab -l; echo "*/30 * * * * /usr/bin/fuel-logrotate") | crontab -
    (crontab -l; echo "*/30 * * * * /bin/dhcp_reschedule.sh") | crontab -

    echo 'Restart neutron-server'
    rm -rf /etc/neutron/plugins/ml2/host_certs/*
    #service keystone restart
    service apache2 restart
    service neutron-server restart
}

compute() {
    if [[ $deploy_dhcp_agent == true ]]; then
        dpkg -l neutron-dhcp-agent
        if [[ $? != 0 ]]; then
            apt-get install -o Dpkg::Options::="--force-confold" -y neutron-metadata-agent
            apt-get install -o Dpkg::Options::="--force-confold" -y neutron-dhcp-agent
            service neutron-metadata-agent stop
            service neutron-dhcp-agent stop
        fi

        # patch linux/dhcp.py to make sure static host route is pushed to instances
        dhcp_py=$(find /usr -name dhcp.py | grep linux)
        dhcp_dir=$(dirname "${dhcp_py}")
        sed -i 's/if (isolated_subnets\[subnet.id\] and/if (True and/g' $dhcp_py
        find $dhcp_dir -name "*.pyc" | xargs rm
        find $dhcp_dir -name "*.pyo" | xargs rm
    fi

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
            dpkg --force-all -i %(dst_dir)s/%(ivs_pkg)s
            if [[ -f %(dst_dir)s/%(ivs_debug_pkg)s ]]; then
                modinfo openvswitch | grep "^version"
                if [[ $? == 0 ]]; then
                    apt-get remove -y openvswitch-datapath-dkms && rmmod openvswitch && modprobe openvswitch
                fi
                apt-get install -y libnl-genl-3-200
                apt-get -f install -y
                dpkg --force-all -i %(dst_dir)s/%(ivs_debug_pkg)s
                apt-get install -y apport
            fi
        elif [[ $skip_ivs_version_check == true ]]; then
            dpkg --force-all -i %(dst_dir)s/%(ivs_pkg)s
            if [[ -f %(dst_dir)s/%(ivs_debug_pkg)s ]]; then
                modinfo openvswitch | grep "^version"
                if [[ $? == 0 ]]; then
                    apt-get remove -y openvswitch-datapath-dkms && rmmod openvswitch && modprobe openvswitch
                fi
                apt-get install -y libnl-genl-3-200
                apt-get -f install -y
                dpkg --force-all -i %(dst_dir)s/%(ivs_debug_pkg)s
                apt-get install -y apport
            fi
        else
            echo "ivs upgrade fails version validation"
        fi
    fi

    # full installation
    if [[ $install_all == true ]]; then
        if [[ -f /etc/init/neutron-plugin-openvswitch-agent.override ]]; then
            cp /etc/init/neutron-plugin-openvswitch-agent.override /etc/init/neutron-bsn-agent.override
        fi

        # stop ovs agent, otherwise, ovs bridges cannot be removed
        pkill neutron-openvswitch-agent
        service neutron-plugin-openvswitch-agent stop

        rm -f /etc/init/neutron-bsn-agent.conf
        rm -f /etc/init/neutron-plugin-openvswitch-agent.conf
        rm -f /usr/bin/neutron-openvswitch-agent

        # remove ovs and linux bridge, example ("br-storage" "br-prv" "br-ex")
        declare -a ovs_br=(%(ovs_br)s)
        len=${#ovs_br[@]}
        for (( i=0; i<$len; i++ )); do
            ovs-vsctl del-br ${ovs_br[$i]}
            brctl delbr ${ovs_br[$i]}
            ip link del dev ${ovs_br[$i]}
        done

        # delete ovs br-int
        while true; do
            service neutron-plugin-openvswitch-agent stop
            rm -f /etc/init/neutron-plugin-openvswitch-agent.conf
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

        # /etc/network/interfaces
        if [[ ${fuel_cluster_id} != 'None' ]]; then
            echo '' > /etc/network/interfaces
            declare -a interfaces=(%(interfaces)s)
            len=${#interfaces[@]}
            for (( i=0; i<$len; i++ )); do
                echo -e 'auto' ${interfaces[$i]} >>/etc/network/interfaces
                echo -e 'iface' ${interfaces[$i]} 'inet manual' >>/etc/network/interfaces
                echo ${interfaces[$i]} | grep '\.'
                if [[ $? == 0 ]]; then
                    intf=$(echo ${interfaces[$i]} | cut -d \. -f 1)
                    echo -e 'vlan-raw-device ' $intf >> /etc/network/interfaces
                fi
                echo -e '\n' >> /etc/network/interfaces
            done
            echo -e 'auto' %(br_fw_admin)s >>/etc/network/interfaces
            echo -e 'iface' %(br_fw_admin)s 'inet static' >>/etc/network/interfaces
            echo -e 'bridge_ports' %(pxe_interface)s >>/etc/network/interfaces
            echo -e 'address' %(br_fw_admin_address)s >>/etc/network/interfaces
        fi

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

        # assign ip to ivs internal ports
        bash /etc/rc.local
    fi

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        service neutron-metadata-agent restart
        service neutron-dhcp-agent restart
    fi

    echo 'Restart openstack-nova-compute and neutron-bsn-agent'
    service nova-compute restart
    service neutron-bsn-agent restart
}

ceph() {
    # copy send_lldp to /bin and start send_lldp service
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp
}

mongo() {
    # copy send_lldp to /bin and start send_lldp service
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp
}


set +e

# Make sure only root can run this script
if [[ "$(id -u)" != "0" ]]; then
   echo -e "Please run as root"
   exit 1
fi

# prepare dependencies
apt-get install ubuntu-cloud-keyring
apt-get install -y linux-headers-$(uname -r) build-essential
apt-get install -y python-dev python-setuptools
apt-get install -y puppet dpkg
apt-get install -y vlan ethtool
apt-get install -y libssl-dev libffi6 libffi-dev
apt-get install -y libnl-genl-3-200
apt-get -f install -y
apt-get install -o Dpkg::Options::="--force-confold" --force-yes -y neutron-common

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    rm -rf /tmp/bsnstacklib-${bsnstacklib_version}
    cd /tmp
    tar -xzf bsnstacklib-${bsnstacklib_version}.tar.gz
    cd /tmp/bsnstacklib-${bsnstacklib_version}
    python setup.py build
    python setup.py install
fi

if [[ $is_controller == true ]]; then
    controller
elif [[ $is_ceph == true ]]; then
    ceph
elif [[ $is_mongo == true ]]; then
    mongo
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

