$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"
$uplinks = [%(uplinks)s]

# install and enable ntp
package { "ntp":
    ensure  => installed,
}
service { "ntpd":
    ensure  => running,
    enable  => true,
    path    => $binpath,
    require => Package['ntp'],
}

# load 8021q module on boot
file {'/etc/sysconfig/modules/8021q.modules':
    ensure  => file,
    mode    => 0777,
    content => "modprobe 8021q",
}
exec { "load 8021q":
    command => "modprobe 8021q",
    path    => $binpath,
}

# lldp
file { "/bin/send_lldp":
    ensure  => file,
    mode    => 0777,
}
file { "/usr/lib/systemd/system/send_lldp.service":
    ensure  => file,
    content => "
[Unit]
Description=send lldp
After=syslog.target network.target
[Service]
Type=simple
ExecStart=/bin/send_lldp --system-desc 5c:16:c7:00:00:04 --system-name %(uname)s -i 10 --network_interface %(uplinks)s
Restart=always
StartLimitInterval=60s
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
",
}->
file { '/etc/systemd/system/multi-user.target.wants/send_lldp.service':
   ensure => link,
   target => '/usr/lib/systemd/system/send_lldp.service',
   notify => Service['send_lldp'],
}
service { "send_lldp":
    ensure  => running,
    enable  => true,
    require => [File['/bin/send_lldp'], File['/etc/systemd/system/multi-user.target.wants/send_lldp.service']],
}

# bond configuration
file { "/etc/sysconfig/network-scripts/ifcfg-%(bond)s":
    ensure  => file,
    content => "
DEVICE=%(bond)s
USERCTL=no
BOOTPROTO=none
ONBOOT=yes
NM_CONTROLLED=no
BONDING_OPTS='mode=4 lacp_rate=1 miimon=50 updelay=15000 xmit_hash_policy=1'
",
}

define bond_intf {
    $uplink = split($name, ',')
    file { "/etc/sysconfig/network-scripts/ifcfg-${uplink}":
        ensure  => file,
        content => "
DEVICE=${uplink}
ONBOOT=yes
NM_CONTROLLED=no
BOOTPROTO=none
USERCTL=no
MASTER=%(bond)s
SLAVE=yes
",
    }
}

bond_intf { $uplinks:
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf debug":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'debug',
  value             => 'True',
}
ini_setting { "neutron.conf report_interval":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'report_interval',
  value             => '60',
}
ini_setting { "neutron.conf agent_down_time":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'agent_down_time',
  value             => '150',
}
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'router',
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '1',
}
ini_setting { "neutron.conf network_scheduler_driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'network_scheduler_driver',
  value             => 'neutron.scheduler.dhcp_agent_scheduler.WeightScheduler',
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
}

# disable neutron-bsn-agent service
service {'neutron-bsn-agent':
    ensure  => stopped,
    enable  => false,
    path    => $binpath,
}

# patch for packstack nova
package { "device-mapper-libs":
  ensure => latest,
  notify => Service['libvirtd'],
}
service { "libvirtd":
  ensure  => running,
  enable  => true,
  path    => $binpath,
  notify  => Service['openstack-nova-compute'],
}
service { "openstack-nova-compute":
  ensure  => running,
  enable  => true,
  path    => $binpath,
}
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# dhcp configuration
if %(deploy_dhcp_agent)s {
    ini_setting { "dhcp agent resync_interval":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'resync_interval',
        value             => '60',
    }
    ini_setting { "dhcp agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.OVSInterfaceDriver',
    }
    ini_setting { "dhcp agent dhcp driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_driver',
        value             => 'bsnstacklib.plugins.bigswitch.dhcp_driver.DnsmasqWithMetaData',
    }
    ini_setting { "force to use dhcp for metadata":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'force_metadata',
        value             => 'True',
    }
    ini_setting { "dhcp agent enable isolated metadata":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_isolated_metadata',
        value             => 'True',
    }
    ini_setting { "dhcp agent disable metadata network":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_metadata_network',
        value             => 'False',
    }
    ini_setting { "dhcp agent disable dhcp_delete_namespaces":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_delete_namespaces',
        value             => 'False',
    }
}

# l3 agent configuration
if %(deploy_l3_agent)s {
    ini_setting { "l3 agent disable metadata proxy":
        ensure            => present,
        path              => '/etc/neutron/l3_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_metadata_proxy',
        value             => 'False',
    }
    ini_setting { "l3 agent external_network_bridge":
        ensure            => present,
        path              => '/etc/neutron/l3_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'external_network_bridge',
        value             => '',
    }
    ini_setting { "l3 agent handle_internal_only_routers":
        ensure            => present,
        path              => '/etc/neutron/l3_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'handle_internal_only_routers',
        value             => 'True',
    }
    service{'neutron-l3-agent':
        ensure  => running,
        enable  => true,
    }
}

# ovs_neutron_plugin for packstack
file { "/etc/neutron/plugins/ml2/openvswitch_agent.ini":
    ensure  => file,
}
ini_setting { "disable tunneling":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'enable_tunneling',
  value             => 'False',
  require           => File['/etc/neutron/plugins/ml2/openvswitch_agent.ini'],
  notify            => Service['neutron-openvswitch-agent'],
}
ini_setting { "clear tunnel type":
  ensure            => absent,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'tunnel_type',
  require           => File['/etc/neutron/plugins/ml2/openvswitch_agent.ini'],
  notify            => Service['neutron-openvswitch-agent'],
}
ini_setting { "tenant network vlan ranges":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'network_vlan_ranges',
  value             => '%(network_vlan_ranges)s',
  notify            => Service['neutron-openvswitch-agent'],
}
ini_setting { "clear tunnel id ranges":
  ensure            => absent,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'tunnel_id_ranges',
  require           => File['/etc/neutron/plugins/ml2/openvswitch_agent.ini'],
  notify            => Service['neutron-openvswitch-agent'],
}
ini_setting { "integration bridge":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'integration_bridge',
  value             => '%(br_int)s',
  notify            => Service['neutron-openvswitch-agent'],
}
ini_setting { "bridge mappings":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'ovs',
  key_val_separator => '=',
  setting           => 'bridge_mappings',
  value             => '%(br_mappings)s',
  notify            => Service['neutron-openvswitch-agent'],
}
# this is agent section of the file
ini_setting { "clear tunnel types":
  ensure            => absent,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'tunnel_types',
  require           => File['/etc/neutron/plugins/ml2/openvswitch_agent.ini'],
  notify            => Service['neutron-openvswitch-agent'],
}
# ensure neutron-openvswitch-agent is running
service { 'neutron-openvswitch-agent':
  ensure  => running,
  enable  => true,
}
