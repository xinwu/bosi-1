
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"
$uplinks = [%(uplinks)s]

define uplink_mtu {
    file_line { "ifconfig $name mtu %(mtu)s":
        path  => '/etc/rc.d/rc.local',
        line  => "ifconfig $name mtu %(mtu)s",
        match => "^ifconfig $name mtu %(mtu)s",
    }
}

# edit rc.local for default gw
file { "/etc/rc.d/rc.local":
    ensure  => file,
    mode    => 0777,
}->
file_line { "remove touch /var/lock/subsys/local":
    path    => '/etc/rc.d/rc.local',
    ensure  => absent,
    line    => "touch /var/lock/subsys/local",
}->
uplink_mtu { $uplinks:
}->
file_line { "remove clear default gw":
    path    => '/etc/rc.d/rc.local',
    ensure  => absent,
    line    => "sudo ip route del default",
}->
file_line { "remove ip route add default":
    path    => '/etc/rc.d/rc.local',
    ensure  => absent,
    line    => "sudo ip route add default via %(default_gw)s",
}->
file_line { "touch /var/lock/subsys/local":
    path    => '/etc/rc.d/rc.local',
    line    => "touch /var/lock/subsys/local",
}->
file_line { "clear default gw":
    path    => '/etc/rc.d/rc.local',
    line    => "sudo ip route del default",
}->
file_line { "add default gw":
    path    => '/etc/rc.d/rc.local',
    line    => "sudo ip route add default via %(default_gw)s",
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

file { '/etc/neutron/dnsmasq-neutron.conf':
    ensure          => file,
    content         => 'dhcp-option-force=26,1400',
}

# ml2
ini_setting { "ml2 type dirvers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'type_drivers',
  value             => 'vlan',
}
ini_setting { "ml2 tenant network types":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'tenant_network_types',
  value             => 'vlan',
}
ini_setting { "ml2 tenant network vlan ranges":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2_type_vlan',
  key_val_separator => '=',
  setting           => 'network_vlan_ranges',
  value             => '%(network_vlan_ranges)s',
}
ini_setting { "ml2 mechanism drivers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'mechanism_drivers',
  value             => 'openvswitch, bsn_ml2',
}
ini_setting { "ml2 restproxy ssl cert directory":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'ssl_cert_directory',
  value             => '/var/lib/neutron',
}
ini_setting { "ml2 restproxy servers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'servers',
  value             => '%(bcf_controllers)s',
}
ini_setting { "ml2 restproxy server auth":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_auth',
  value             => '%(bcf_controller_user)s:%(bcf_controller_passwd)s',
}
ini_setting { "ml2 restproxy server ssl":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_ssl',
  value             => 'True',
}
ini_setting { "ml2 restproxy auto sync on failure":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auto_sync_on_failure',
  value             => 'True',
}
ini_setting { "ml2 restproxy consistency interval":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'consistency_interval',
  value             => 60,
}
ini_setting { "ml2 restproxy neutron_id":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'neutron_id',
  value             => %(neutron_id)s,
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
        value             => 'neutron.agent.linux.dhcp.Dnsmasq',
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
        value             => 'True',
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
        value             => 'True',
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
}

# config /etc/neutron/neutron.conf
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
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
}
ini_setting { "neutron.conf allow_automatic_l3agent_failover":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'allow_automatic_l3agent_failover',
  value             => 'True',
}

service{'neutron-bsn-agent':
    ensure  => stopped,
    enable  => false,
}

service { 'neutron-openvswitch-agent':
  ensure  => running,
  enable  => true,
}

