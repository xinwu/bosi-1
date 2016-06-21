#!/bin/bash

export LIBGUESTFS_BACKEND=direct

image_dir="/home/stack/images"

virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload python-networking-bigswitch-${bsnstacklib_version}-1.el7.centos.noarch.rpm:/root/
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload openstack-neutron-bigswitch-lldp-${bsnstacklib_version}-1.el7.centos.noarch.rpm:/root/
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload openstack-neutron-bigswitch-agent-${bsnstacklib_version}-1.el7.centos.noarch.rpm:/root/
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload python-horizon-bsn-${horizon_bsn_version}-1.el7.centos.noarch.rpm:/root/
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload ivs-${ivs_version}-1.el7.centos.x86_64.rpm:/root/
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload ivs-debuginfo-${ivs_version}-1.el7.centos.x86_64.rpm:/root/

virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload ifup-ivs:/etc/sysconfig/network-scripts/ifup-ivs
virt-customize -a ${image_dir}/overcloud-full.qcow2 --run-command 'chmod a+x /etc/sysconfig/network-scripts/ifup-ivs'
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload ifdown-ivs:/etc/sysconfig/network-scripts/ifdown-ivs
virt-customize -a ${image_dir}/overcloud-full.qcow2 --run-command 'chmod a+x /etc/sysconfig/network-scripts/ifdown-ivs'
virt-customize -a ${image_dir}/overcloud-full.qcow2 --upload assign-ivs-ip:/etc/sysconfig/network-scripts/assign-ivs-ip
virt-customize -a ${image_dir}/overcloud-full.qcow2 --run-command 'chmod a+x /etc/sysconfig/network-scripts/assign-ivs-ip'

virt-customize -a ${image_dir}/overcloud-full.qcow2 --firstboot startup.sh

