#!/bin/bash

is_controller=%(is_controller)s

controller() {

    PKGS=/tmp/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"python-networking-bigswitch"* ]]; then
            yum remove -y python-networking-bigswitch
            yum install -y $pkg
            neutron-db-manage upgrade heads
            systemctl restart neutron-server
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"openstack-neutron-bigswitch-lldp"* ]]; then
            yum remove -y openstack-neutron-bigswitch-lldp
            yum install -y $pkg
            systemctl restart neutron-bsn-lldp
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"openstack-neutron-bigswitch-agent"* ]]; then
            yum remove -y openstack-neutron-bigswitch-agent
            yum install -y $pkg
            systemctl stop neutron-bsn-agent
            systemctl disable neutron-bsn-agent
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"python-horizon-bsn"* ]]; then
            yum remove -y python-horizon-bsn
            yum install -y $pkg
            systemctl restart httpd
            break
        fi
    done

}

compute() {

    PKGS=/tmp/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"python-networking-bigswitch"* ]]; then
            yum remove -y python-networking-bigswitch
            yum install -y $pkg
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"openstack-neutron-bigswitch-agent"* ]]; then
            yum remove -y openstack-neutron-bigswitch-agent
            yum install -y $pkg
            systemctl restart neutron-bsn-agent
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"ivs-debuginfo"* ]]; then
            yum install -y $pkg
            yum reinstall -y $pkg
            break
        fi
    done

    for pkg in $PKGS
    do
        if [[ $pkg == *"ivs"* ]]; then
            yum install -y $pkg
            yum reinstall -y $pkg
            systemctl restart ivs
            break
        fi
    done
}


set +e

# Make sure only root can run this script
if [ "$(id -u)" != "0" ]; then
    echo -e "Please run as root"
    exit 1
fi

if [[ $is_controller == true ]]; then
    controller
else
    compute
fi

set -e

exit 0

