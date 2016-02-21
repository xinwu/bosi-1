# all of the exec statements use this path
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"
$uplinks = [%(uplinks)s]

# lldp
file { "/bin/send_lldp":
    ensure  => file,
    mode    => 0777,
}
file { "/etc/init/send_lldp.conf":
    ensure  => file,
    content => "
description \"BCF LLDP\"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    exec /bin/send_lldp --system-desc 5c:16:c7:00:00:04 --system-name $(uname -n) -i 10 --network_interface %(uplinks)s
end script
",
}
service { "send_lldp":
    ensure  => running,
    enable  => true,
    require => [File['/bin/send_lldp'], File['/etc/init/send_lldp.conf']],
}

# uplink mtu
define uplink_mtu {
    file_line { "ifconfig $name mtu %(mtu)s":
        path  => '/etc/rc.local',
        line  => "ifconfig $name mtu %(mtu)s",
        match => "^ifconfig $name mtu %(mtu)s",
    }
}

# edit rc.local for cron job and default gw
file { "/etc/rc.local":
    ensure  => file,
    mode    => 0777,
}->
file_line { "remove exit 0":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "exit 0",
}->
uplink_mtu { $uplinks:
}->
file_line { "remove crontab -r":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "crontab -r",
}->
file_line { "remove fuel-logrotate":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "(crontab -l; echo \"*/30 * * * * /usr/bin/fuel-logrotate\") | crontab -",
}->
file_line { "remove dhcp_reschedule.sh":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "(crontab -l; echo \"*/30 * * * * /bin/dhcp_reschedule.sh\") | crontab -",
}->
file_line { "remove clear default gw":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "ip route del default",
}->
file_line { "remove ip route add default":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "ip route add default via %(default_gw)s",
}->
file_line { "clear default gw":
    path    => '/etc/rc.local',
    line    => "ip route del default",
}->
file_line { "add default gw":
    path    => '/etc/rc.local',
    line    => "ip route add default via %(default_gw)s",
}->
file_line { "clean up cron job":
    path    => '/etc/rc.local',
    line    => "crontab -r",
}->
file_line { "add cron job to rotate log":
    path    => '/etc/rc.local',
    line    => "(crontab -l; echo \"*/30 * * * * /usr/bin/fuel-logrotate\") | crontab -",
}->
file_line { "add cron job to reschedule dhcp":
    path    => '/etc/rc.local',
    line    => "(crontab -l; echo \"*/30 * * * * /bin/dhcp_reschedule.sh\") | crontab -",
}->
file_line { "add exit 0":
    path    => '/etc/rc.local',
    line    => "exit 0",
}

# config /etc/neutron/neutron.conf
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

# set the correct properties in ml2_conf.ini on compute as well
# config /etc/neutron/plugins/ml2/ml2_conf.ini
ini_setting { "ml2 type dirvers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'type_drivers',
  value             => 'vlan',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 tenant network types":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'tenant_network_types',
  value             => 'vlan',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 tenant network vlan ranges":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2_type_vlan',
  key_val_separator => '=',
  setting           => 'network_vlan_ranges',
  value             => '%(network_vlan_ranges)s',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 mechanism drivers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'mechanism_drivers',
  value             => 'openvswitch,bsn_ml2',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy ssl cert directory":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'ssl_cert_directory',
  value             => '/etc/neutron/plugins/ml2',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy servers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'servers',
  value             => '%(bcf_controllers)s',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy server auth":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_auth',
  value             => '%(bcf_controller_user)s:%(bcf_controller_passwd)s',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy server ssl":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_ssl',
  value             => 'True',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy auto sync on failure":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auto_sync_on_failure',
  value             => 'True',
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy consistency interval":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'consistency_interval',
  value             => 60,
  notify            => Service['neutron-plugin-openvswitch-agent'],
}
ini_setting { "ml2 restproxy neutron_id":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'neutron_id',
  value             => %(neutron_id)s,
  notify            => Service['neutron-plugin-openvswitch-agent'],
}

# change ml2 ownership
file { '/etc/neutron/plugins/ml2':
  owner   => neutron,
  group   => neutron,
  recurse => true,
  notify  => Service['neutron-plugin-openvswitch-agent'],
}

# make sure neutron-bsn-agent is stopped
service {'neutron-bsn-agent':
  ensure  => stopped,
  enable  => false,
}

# ensure neutron-plugin-openvswitch-agent is running
file { "/etc/init/neutron-plugin-openvswitch-agent.conf":
    ensure  => file,
    mode    => 0644,
}
service { 'neutron-plugin-openvswitch-agent':
  ensure     => 'running',
  enable     => 'true',
  provider   => 'upstart',
  hasrestart => 'true',
  hasstatus  => 'true',
  subscribe  => [File['/etc/init/neutron-plugin-openvswitch-agent.conf']],
}

# l3 agent configuration
if %(deploy_l3_agent)s {
    ini_setting { "l3 agent enable metadata proxy":
      ensure            => present,
      path              => '/etc/neutron/l3_agent.ini',
      section           => 'DEFAULT',
      key_val_separator => '=',
      setting           => 'enable_metadata_proxy',
      value             => 'False',
    }
    # don't specify bridge for external networks so
    # they are treated like a normal VLAN network
    ini_setting { "l3 agent external network bridge":
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

file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# dhcp configuration
if %(deploy_dhcp_agent)s {
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

