#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
install_all=%(install_all)s
deploy_dhcp_agent=%(deploy_dhcp_agent)s
deploy_l3_agent=%(deploy_l3_agent)s
ivs_version=%(ivs_version)s
is_controller=%(is_controller)s
is_ceph=%(is_ceph)s
is_cinder=%(is_cinder)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
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

    # deploy horizon plugin
    cp /usr/local/lib/python2.7/dist-packages/horizon_bsn/enabled/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/

    echo 'Restart neutron-server'
    rm -rf /var/lib/neutron/host_certs/*
    #service keystone restart
    service apache2 restart
    service neutron-server restart
}

compute() {
    # update bond mode to balance-xor
    sed -i 's/bond-mode.*/bond-mode 4/' /etc/network/interfaces.d/ifcfg-%(bond)s
    grep -q -e 'bond-lacp-rate 1' /etc/network/interfaces.d/ifcfg-%(bond)s || sed -i '$a\bond-lacp-rate 1' /etc/network/interfaces.d/ifcfg-%(bond)s

    # copy send_lldp to /bin
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Deploy and stop neutron-metadata-agent and neutron-dhcp-agent'
        apt-get install -o Dpkg::Options::="--force-confold" -y neutron-metadata-agent
        apt-get install -o Dpkg::Options::="--force-confold" -y neutron-dhcp-agent
        service neutron-metadata-agent stop
        mv /etc/init/neutron-metadata-agent.conf /etc/init/neutron-metadata-agent.conf.disabled
        service neutron-dhcp-agent stop
        mv /etc/init/neutron-dhcp-agent.conf /etc/init/neutron-dhcp-agent.conf.disabled
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo "Deploy and stop neutron-l3-agent"
        apt-get install -o Dpkg::Options::="--force-confold" -y neutron-l3-agent
        service neutron-l3-agent stop
        mv /etc/init/neutron-l3-agent.conf /etc/init/neutron-l3-agent.conf.disabled
    fi

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        mv /etc/init/neutron-metadata-agent.conf.disabled /etc/init/neutron-metadata-agent.conf
        service neutron-metadata-agent restart
        mv /etc/init/neutron-dhcp-agent.conf.disabled /etc/init/neutron-dhcp-agent.conf
        service neutron-dhcp-agent restart
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo "Restart neutron-l3-agent"
        mv /etc/init/neutron-l3-agent.conf.disabled /etc/init/neutron-l3-agent.conf
        service neutron-l3-agent restart
    fi
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

