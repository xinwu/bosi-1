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
    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    echo 'Stop and disable neutron-metadata-agent, neutron-dhcp-agent and neutron-l3-agent'
    if [[ ${fuel_cluster_id} != 'None' ]]; then
        crm resource stop p_neutron-dhcp-agent
        crm resource stop p_neutron-metadata-agent
        crm resource stop p_neutron-l3-agent
        sleep 15
        crm configure delete p_neutron-dhcp-agent
        crm configure delete p_neutron-metadata-agent
        crm configure delete p_neutron-l3-agent
    fi
    service neutron-metadata-agent stop
    update-rc.d neutron-metadata-agent disable
    service neutron-dhcp-agent stop
    update-rc.d neutron-dhcp-agent disable
    service neutron-l3-agent stop
    update-rc.d neutron-l3-agent disable
    

    if [[ $deploy_horizon_patch == true ]]; then
        # enable lb
        sed -i 's/'"'"'enable_lb'"'"': False/'"'"'enable_lb'"'"': True/g' %(horizon_base_dir)s/openstack_dashboard/local/local_settings.py

        # chmod neutron config since bigswitch horizon patch reads neutron config as well
        chmod -R a+r /etc/neutron
        chmod -R a+x /etc/neutron

        # deploy bcf horizon patch to controller node
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
            find "%(horizon_base_dir)s" -name "*.pyc" | xargs -0 /bin/rm -f
            find "%(horizon_base_dir)s" -name "*.pyo" | xargs -0 /bin/rm -f

            # patch neutron api.py to work around oslo bug
            # https://bugs.launchpad.net/oslo-incubator/+bug/1328247
            # https://review.openstack.org/#/c/130892/1/openstack/common/fileutils.py
            neutron_api_py=$(find /usr -name api.py | grep neutron | grep db | grep -v plugins)
            neutron_api_dir=$(dirname "${neutron_api_py}")
            sed -i 's/from neutron.openstack.common import log as logging/import logging/g' $neutron_api_py
            find $neutron_api_dir -name "*.pyc" | xargs rm
            find $neutron_api_dir -name "*.pyo" | xargs rm
        fi
    fi

    echo 'Restart neutron-server'
    rm -rf /etc/neutron/plugins/ml2/host_certs/*
    service keystone restart
    service apache2 restart
    service neutron-server restart

    # schedule cron job to reschedule network in case dhcp agent fails
    chmod a+x /bin/dhcp_reschedule.sh
    crontab -r
    (crontab -l; echo "*/30 * * * * /usr/bin/fuel-logrotate") | crontab -
    (crontab -l; echo "*/30 * * * * /bin/dhcp_reschedule.sh") | crontab -
}

compute() {
    # update bond mode to balance-xor
    ifdown %(bond)s
    sed -i 's/bond-mode.*/bond-mode balance-xor/' /etc/network/interfaces.d/ifcfg-%(bond)s
    # ifup bond0 doesn't bring up slave interfaces. ifup -a applies to all auto interfaces
    ifup -a

    # copy send_lldp to /bin
    sudo cp %(dst_dir)s/send_lldp /bin/
    sudo chmod 777 /bin/send_lldp

    # patch linux/dhcp.py to make sure static host route is pushed to instances
    apt-get install -o Dpkg::Options::="--force-confold" -y neutron-metadata-agent
    apt-get install -o Dpkg::Options::="--force-confold" -y neutron-dhcp-agent
    apt-get install -o Dpkg::Options::="--force-confold" -y neutron-l3-agent
    service neutron-metadata-agent stop
    update-rc.d neutron-metadata-agent disable
    service neutron-dhcp-agent stop
    update-rc.d neutron-dhcp-agent disable
    service neutron-l3-agent stop
    update-rc.d neutron-l3-agent disable
    dhcp_py=$(find /usr -name dhcp.py | grep linux)
    dhcp_dir=$(dirname "${dhcp_py}")
    sed -i 's/if (isolated_subnets\[subnet.id\] and/if (True and/g' $dhcp_py
    find $dhcp_dir -name "*.pyc" | xargs rm
    find $dhcp_dir -name "*.pyo" | xargs rm

    # deploy bcf
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    if [[ $deploy_dhcp_agent == true ]]; then
        echo 'Restart neutron-metadata-agent and neutron-dhcp-agent'
        service neutron-metadata-agent restart
        update-rc.d neutron-metadata-agent defaults
        service neutron-dhcp-agent restart
        update-rc.d neutron-dhcp-agent defaults
    fi

    if [[ $deploy_l3_agent == true ]]; then
        echo "Restart neutron-l3-agent"
        service neutron-l3-agent restart
        update-rc.d neutron-l3-agent defaults
    fi
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

