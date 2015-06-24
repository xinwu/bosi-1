
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
    exec /bin/send_lldp --system-desc 5c:16:c7:00:00:00 --system-name $(uname -n) -i 30 --network_interface %(uplinks)s
end script
",
}
service { "send_lldp":
    ensure  => running,
    enable  => true,
    require => [File['/bin/send_lldp'], File['/etc/init/send_lldp.conf']],
}

# comment out heat domain related configurations
$heat_config = file('/etc/heat/heat.conf','/dev/null')
if($heat_config != '') {
    ini_setting { "heat stack_domain_admin_password":
        ensure            => absent,
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'stack_domain_admin_password',
        notify            => Service['heat-engine'],
    }
    ini_setting { "heat stack_domain_admin":
        ensure            => absent,
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'stack_domain_admin',
        notify            => Service['heat-engine'],
    }
    ini_setting { "heat stack_user_domain":
        ensure            => absent,
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'stack_user_domain',
        notify            => Service['heat-engine'],
    }
    ini_setting {"heat_deferred_auth_method":
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        setting           => 'deferred_auth_method',
        value             => 'password',
        ensure            => present,
        notify            => Service['heat-engine'],
    }
    service { 'heat-engine':
        ensure     => running,
        provider   => 'upstart',
        enable     => true,
    }
}

# assign default gw
file { "/etc/rc.local":
    ensure  => file,
    mode    => 0777,
}->
file_line { "remove exit 0":
    path    => '/etc/rc.local',
    ensure  => absent,
    line    => "exit 0",
}->
file_line { "clear default gw":
    path    => '/etc/rc.local',
    line    => "ip route del default",
    match   => "^ip route del default$",
}->
file_line { "add default gw":
    path    => '/etc/rc.local',
    line    => "ip route add default via %(default_gw)s",
    match   => "^ip route add default via %(default_gw)s",
}->
file_line { "add exit 0":
    path    => '/etc/rc.local',
    line    => "exit 0",
}

# make sure known_hosts is cleaned up
file { "/root/.ssh/known_hosts":
    ensure => absent,
}

# keystone paste config
ini_setting { "keystone paste config":
    ensure            => present,
    path              => '/etc/keystone/keystone.conf',
    section           => 'paste_deploy',
    key_val_separator => '=',
    setting           => 'config_file',
    value             => '/etc/keystone/keystone-paste.ini',
}

# reserve keystone ephemeral port
exec { "reserve keystone port":
    command => "sysctl -w 'net.ipv4.ip_local_reserved_ports=49000,35357,41055,58882'",
    path    => $binpath,
}
file_line { "reserve keystone port":
    path  => '/etc/sysctl.conf',
    line  => 'net.ipv4.ip_local_reserved_ports=49000,35357,41055,58882',
    match => '^net.ipv4.ip_local_reserved_ports.*$',
}

# load 8021q module on boot
package { 'vlan':
    ensure  => latest,
}
file_line {'load 8021q on boot':
    path    => '/etc/modules',
    line    => '8021q',
    match   => '^8021q$',
    require => Package['vlan'],
}
exec { "load 8021q":
    command => "modprobe 8021q",
    path    => $binpath,
    require => Package['vlan'],
}

# install and enable ntp
package { "ntp":
    ensure  => installed,
}
service { "ntp":
    ensure  => running,
    enable  => true,
    require => Package['ntp'],
}

# add pkg for ivs debug logging
package { 'binutils':
   ensure => latest,
}

# purge bcf controller public key
exec { 'purge bcf key':
    command => "rm -rf /etc/neutron/plugins/ml2/host_certs/*",
    path    => $binpath,
    notify  => Service['neutron-server'],
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'bsn_l3',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '2',
  notify            => Service['neutron-server'],
}

# config /etc/neutron/plugin.ini
ini_setting { "neutron plugin.ini firewall_driver":
  ensure            => present,
  path              => '/etc/neutron/plugin.ini',
  section           => 'securitygroup',
  key_val_separator => '=',
  setting           => 'firewall_driver',
  value             => 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron plugin.ini enable_security_group":
  ensure            => present,
  path              => '/etc/neutron/plugin.ini',
  section           => 'securitygroup',
  key_val_separator => '=',
  setting           => 'enable_security_group',
  value             => 'True',
  notify            => Service['neutron-server'],
}

# config /etc/neutron/dhcp_agent.ini
ini_setting { "dhcp agent interface driver":
  ensure            => present,
  path              => '/etc/neutron/dhcp_agent.ini',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'interface_driver',
  value             => 'neutron.agent.linux.interface.IVSInterfaceDriver',
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
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# disable l3 agent
service { 'neutron-l3-agent':
  ensure  => stopped,
  enable  => false,
}
ini_setting { "l3 agent disable metadata proxy":
  ensure            => present,
  path              => '/etc/neutron/l3_agent.ini',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'enable_metadata_proxy',
  value             => 'False',
}

# config /etc/neutron/plugins/ml2/ml2_conf.ini 
ini_setting { "ml2 type dirvers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'type_drivers',
  value             => 'vlan',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 tenant network types":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'tenant_network_types',
  value             => 'vlan',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 tenant network vlan ranges":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2_type_vlan',
  key_val_separator => '=',
  setting           => 'network_vlan_ranges',
  value             => '%(network_vlan_ranges)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 mechanism drivers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'mechanism_drivers',
  value             => 'bsn_ml2',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy ssl cert directory":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'ssl_cert_directory',
  value             => '/etc/neutron/plugins/ml2',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy servers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'servers',
  value             => '%(bcf_controllers)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy server auth":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_auth',
  value             => '%(bcf_controller_user)s:%(bcf_controller_passwd)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy server ssl":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_ssl',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy auto sync on failure":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auto_sync_on_failure',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy consistency interval":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'consistency_interval',
  value             => 60,
  notify            => Service['neutron-server'],
}

# change ml2 ownership
file { '/etc/neutron/plugins/ml2':
  owner   => neutron,
  group   => neutron,
  recurse => true,
  notify  => Service['neutron-server'],
}

# neutron-server, neutron-dhcp-agent and neutron-metadata-agent
service { 'neutron-server':
  ensure     => running,
  provider   => 'upstart',
  enable     => true,
}
service { 'neutron-dhcp-agent':
  ensure     => stopped,
  enable     => false,
}
service { 'neutron-metadata-agent':
  ensure  => stopped,
  enable  => false,
}


