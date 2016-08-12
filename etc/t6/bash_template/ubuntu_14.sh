#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
is_ceph=%(is_ceph)s
is_cinder=%(is_cinder)s
is_mongo=%(is_mongo)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
skip_ivs_version_check=%(skip_ivs_version_check)s
pip_proxy=%(pip_proxy)s

controller() {
    # copy send_lldp to /bin
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # bsnstacklib installed and property files updated. now perform live db migration
    echo "Performing live DB migration for Neutron.."
    if [[ $openstack_release == 'kilo' || $openstack_release == 'kilo_v2' ]]; then
        pip install --upgrade 'alembic<0.8.1,>=0.7.2'
        neutron-db-manage upgrade head
        neutron-db-manage --service bsn_service_plugin upgrade head
    else
        neutron-db-manage upgrade heads
    fi

    echo 'Stop and disable neutron-metadata-agent and neutron-dhcp-agent'
    if [[ ${fuel_cluster_id} != 'None' ]]; then
        crm resource stop p_neutron-l3-agent
        sleep 10
        crm resource cleanup p_neutron-l3-agent
        sleep 10
        crm configure delete p_neutron-l3-agent
    fi
    service neutron-l3-agent stop
    rm -f /etc/init/neutron-l3-agent.conf
    service neutron-bsn-agent stop
    rm -f /etc/init/neutron-bsn-agent.conf


    # deploy horizon plugin
    cp /usr/local/lib/python2.7/dist-packages/horizon_bsn/enabled/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/

    echo 'Restart neutron-server'
    rm -rf /var/lib/neutron/host_certs/*
    #service keystone restart
    service apache2 restart
    service neutron-server restart
}

compute() {
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

        # stop neutron-l3-agent
        pkill neutron-l3-agent
        service neutron-l3-agent stop

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

    echo 'Restart ivs, neutron-bsn-agent'
    service ivs restart
    service neutron-bsn-agent restart
}

ceph() {
    # copy send_lldp to /bin and start send_lldp service
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp
}

cinder() {
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
easy_install pip
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
elif [[ $is_ceph == true ]]; then
    ceph
elif [[ $is_cinder == true ]]; then
    cinder
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
