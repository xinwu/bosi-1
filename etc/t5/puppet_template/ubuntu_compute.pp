# all of the exec statements use this path
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

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
    exec /bin/send_lldp --system-desc 5c:16:c7:00:00:00 --system-name $(uname -n) -i 10 --network_interface %(uplinks)s
end script
",
}
service { "send_lldp":
    ensure  => running,
    enable  => true,
    require => [File['/bin/send_lldp'], File['/etc/init/send_lldp.conf']],
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
  value             => 'router,lbaas',
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '2',
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
}

# make sure neutron-bsn-agent is stopped
# config neutron-bsn-agent conf
file { '/etc/init/neutron-bsn-agent.conf':
    ensure => present,
    content => "
description \"Neutron BSN Agent\"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    exec /usr/local/bin/neutron-bsn-agent --config-file=/etc/neutron/neutron.conf --config-file=/etc/neutron/plugins/ml2/ml2_conf.ini --log-file=/var/log/neutron/neutron-bsn-agent.log
end script
",
}
file { '/etc/init.d/neutron-bsn-agent':
    ensure => link,
    target => '/lib/init/upstart-job',
    notify => Service['neutron-bsn-agent'],
}
service {'neutron-bsn-agent':
    ensure     => 'stopped',
    enable     => 'false',
    provider   => 'upstart',
    subscribe  => [File['/etc/init/neutron-bsn-agent.conf'], File['/etc/init.d/neutron-bsn-agent']],
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
    ini_setting { "l3 agent external network bridge":
      ensure            => present,
      path              => '/etc/neutron/l3_agent.ini',
      section           => 'DEFAULT',
      key_val_separator => '=',
      setting           => 'external_network_bridge',
      value             => '',
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
        value             => 'bsnstacklib.plugins.bigswitch.dhcp_driver.DnsmasqWithMetaData',
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

# haproxy
if %(deploy_haproxy)s {
    package { "neutron-lbaas-agent":
        ensure  => installed,
    }
    package { "haproxy":
        ensure  => installed,
    }
    ini_setting { "haproxy agent periodic interval":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'periodic_interval',
        value             => '10',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.OVSInterfaceDriver',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent device driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'device_driver',
        value             => 'neutron.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    service { "haproxy":
        ensure            => running,
        enable            => true,
        require           => Package['haproxy'],
    }
    service { "neutron-lbaas-agent":
        ensure            => running,
        enable            => true,
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
    }
}
