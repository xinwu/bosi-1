
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

# TODO install selinux policies
#Package { allow_virtual => true }
#class { selinux:
#  mode => '%(selinux_mode)s'
#}
#selinux::module { 'selinux-bcf':
#  ensure => 'present',
#  source => 'puppet:///modules/selinux/centos.te',
#}

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

# fix centos symbolic link problem for ivs debug logging
file { '/usr/lib64/debug':
   ensure => link,
   target => '/lib/debug',
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
  value             => 'router,lbaas',
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
ini_setting { "ensure absent of neutron.conf service providers":
  ensure            => absent,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
}->
ini_setting { "neutron.conf service providers":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
  value             => 'LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default',
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
  value             => 'openvswitch,bigswitch',
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
    package { "haproxy":
        ensure  => installed,
    }
    package { "keepalived":
        ensure  => installed,
    }
    ini_setting { "haproxy agent periodic interval":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'periodic_interval',
        value             => '10',
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.OVSInterfaceDriver',
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent device driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'device_driver',
        value             => 'neutron.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver',
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
        require           => Package['haproxy'],
    }
    service { "keepalived":
        ensure            => running,
        enable            => true,
        require           => Package['keepalived'],
    }
    file_line { "net.ipv4.ip_nonlocal_bind=1":
        path  => '/etc/sysctl.conf',
        line  => "net.ipv4.ip_nonlocal_bind=1",
        match => "^net.ipv4.ip_nonlocal_bind=1",
    }
}


