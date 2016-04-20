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
deploy_horizon_patch=%(deploy_horizon_patch)s
fuel_cluster_id=%(fuel_cluster_id)s
openstack_release=%(openstack_release)s
pip_proxy=%(pip_proxy)s

controller() {
    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    # bsnstacklib installed and property files updated. now perform live db migration
    echo "Performing live DB migration for Neutron.."
    if [[ $openstack_release == 'kilo' || $openstack_release == 'kilo_v2' ]]; then
        neutron-db-manage --service bsn_service_plugin upgrade head
    else
        neutron-db-manage upgrade heads
    fi

    echo 'Stop and disable neutron-metadata-agent, neutron-dhcp-agent and neutron-l3-agent'
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
    mv /etc/init/neutron-metadata-agent.conf /etc/init/neutron-metadata-agent.conf.disabled
    service neutron-dhcp-agent stop
    mv /etc/init/neutron-dhcp-agent.conf /etc/init/neutron-dhcp-agent.conf.disabled
    service neutron-l3-agent stop
    mv /etc/init/neutron-l3-agent.conf /etc/init/neutron-l3-agent.conf.disabled


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

        # patch linux/dhcp.py to make sure static host route is pushed to instances
        dhcp_py=$(find /usr -name dhcp.py | grep linux)
        dhcp_dir=$(dirname "${dhcp_py}")
        sed -i 's/if (isolated_subnets\[subnet.id\] and/if (True and/g' $dhcp_py
        find $dhcp_dir -name "*.pyc" | xargs rm
        find $dhcp_dir -name "*.pyo" | xargs rm
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
cat /etc/apt/sources.list | grep "http://archive.ubuntu.com/ubuntu"
if [[ $? != 0 ]]; then
    release=$(lsb_release -sc)
    echo -e "\ndeb http://archive.ubuntu.com/ubuntu $release main\n" >> /etc/apt/sources.list
fi
apt-get install ubuntu-cloud-keyring
if [[ $openstack_release == 'juno' ]]; then
    echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
    "trusty-updates/juno main" > /etc/apt/sources.list.d/cloudarchive-juno.list
fi
apt-get update -y
apt-get install -y linux-headers-$(uname -r) build-essential
apt-get install -y python-dev python-setuptools
apt-get install -y puppet dpkg
apt-get install -y vlan ethtool
apt-get install -y libssl-dev libffi6 libffi-dev
apt-get install -y libnl-genl-3-200
apt-get -f install -y
apt-get install -o Dpkg::Options::="--force-confold" --force-yes -y neutron-common
easy_install pip
puppet module install --force puppetlabs-inifile
puppet module install --force puppetlabs-stdlib

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    sleep 2
    pip uninstall -y bsnstacklib
    sleep 2
    if [[ $pip_proxy == false ]]; then
        pip install --upgrade "bsnstacklib>%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
        pip install --upgrade "horizon-bsn>%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
    else
        pip --proxy $pip_proxy  install --upgrade "bsnstacklib>%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
        pip --proxy $pip_proxy  install --upgrade "horizon-bsn>%(bsnstacklib_version_lower)s,<%(bsnstacklib_version_upper)s"
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

