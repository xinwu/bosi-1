#!/bin/bash

is_controller=%(is_controller)s

controller() {

    PKGS=%(dst_dir)s/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"python-networking-bigswitch"* ]]; then
            rpm -ivh --force $pkg
            neutron-db-manage upgrade heads
            systemctl restart neutron-server
        fi
        if [[ $pkg == *"horizon-bsn"* ]]; then
            rpm -ivh --force $pkg
            systemctl restart httpd
        fi
    done
}

compute() {

    PKGS=%(dst_dir)s/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"python-networking-bigswitch"* ]]; then
            rpm -ivh --force $pkg
        fi
        if [[ $pkg == *"openstack-neutron-bigswitch-agent"* ]]; then
            rpm -ivh --force $pkg
            systemctl restart neutron-bsn-agent
        fi
        if [[ $pkg == *"ivs"* ]]; then
            rpm -ivh --force $pkg
            systemctl restart ivs
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

