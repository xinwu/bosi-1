#!/bin/bash

# This template reschedule network to
# different dhcp agent if their dhcp
# agent is offline

# disable for now until dhcp agent bug get fixed
exit 0

release="%(openstack_release)s"
if [[ $release != 'juno' ]]; then
    exit 0
fi

source %(openrc)s
keystone tenant-list
if [[ $? != 0 ]]; then
    echo 'Unable to establish connection for ospurge'
    exit 1
fi

up_dhcp_agents=$(neutron agent-list -c id -c agent_type -c alive | grep "DHCP agent"  | grep ':-)' | shuf | head -n 1 | awk '{ print $2 }')
down_dhcp_agents=$(neutron agent-list -c id -c agent_type -c alive | grep "DHCP agent"  | grep -v ':-)' | awk '{ print $2 }')

len=${#up_dhcp_agents[@]}
i=0
for down_dhcp_agent in $down_dhcp_agents; do
    nets=$(neutron net-list-on-dhcp-agent $down_dhcp_agent -c id -f csv | grep -v '"id"' | awk -F '"' '{ print $2 }')
    for net in $nets; do
        neutron dhcp-agent-network-remove $down_dhcp_agent $net
        if [[ $i -ge $((len-1)) ]]; then
            i=0
        fi
        neutron dhcp-agent-network-add ${up_dhcp_agents[$i]} $net
        ((i++))
    done
done
