#!/bin/bash

bsnstacklib_version="2015.3.14"
horizon_bsn_version="2015.3.7"
ivs_version="3.6.0"

rpm -ivh --force /root/python-networking-bigswitch-${bsnstacklib_version}-1.el7.centos.noarch.rpm
rpm -ivh --force /root/openstack-neutron-bigswitch-agent-${bsnstacklib_version}-1.el7.centos.noarch.rpm
rpm -ivh --force /root/openstack-neutron-bigswitch-lldp-${bsnstacklib_version}-1.el7.centos.noarch.rpm
rpm -ivh --force /root/python-horizon-bsn-${horizon_bsn_version}-1.el7.centos.noarch.rpm
rpm -ivh --force /root/ivs-${ivs_version}-1.el7.centos.x86_64.rpm
rpm -ivh --force /root/ivs-debuginfo-${ivs_version}-1.el7.centos.x86_64.rpm
systemctl enable neutron-bsn-lldp.service
systemctl restart neutron-bsn-lldp.service
