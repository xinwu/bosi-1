#!/bin/bash

is_controller=%(is_controller)s
is_ceph=%(is_ceph)s
is_cinder=%(is_cinder)s
is_mongo=%(is_mongo)s

install_pkg {
    pkg=$1
    cd %(dst_dir)s/upgrade
    tar -xzf $pkg
    dir=${pkg::-7}
    cd $dir
    python setup.py build
    python setup.py install
}

controller() {

    PKGS=%(dst_dir)s/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"bsnstacklib"* ]]; then
            install_pkg $pkg
            neutron-db-manage upgrade heads
            service neutron-server restart
        fi
        if [[ $pkg == *"horizon-bsn"* ]]; then
            install_pkg $pkg
            service apache2 restart
        fi
    done
}

compute() {

    PKGS=%(dst_dir)s/upgrade/*
    for pkg in $PKGS
    do
        if [[ $pkg == *"ivs"* ]]; then
            dpkg --force-all -i $pkg
            service ivs restart
        fi
        if [[ $pkg == *"bsnstacklib"* ]]; then
            install_pkg $pkg
            service neutron-bsn-agent restart
        fi
    done
}

ceph() {
}

cinder() {
}

mongo() {
}


set +e

# Make sure only root can run this script
if [[ "$(id -u)" != "0" ]]; then
   echo -e "Please run as root"
   exit 1
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

set -e

exit 0

