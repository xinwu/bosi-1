
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

# uplink mtu
define uplink_mtu {
    file_line { "ifconfig $name mtu %(mtu)s":
        path  => '/etc/rc.local',
        line  => "ifconfig $name mtu %(mtu)s",
        match => "^ifconfig $name mtu %(mtu)s",
    }
}

# edit rc.local for cron job and default gw
$uplinks = [%(uplinks)s]
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

# load bonding module
file_line {'load bonding on boot':
    path    => '/etc/modules',
    line    => 'bonding',
    match   => '^bonding$',
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
ini_setting { "neutron.conf debug":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'debug',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf report_interval":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'report_interval',
  value             => '60',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf agent_down_time":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'agent_down_time',
  value             => '150',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'bsn_l3,bsn_service_plugin',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '1',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf network_scheduler_driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'network_scheduler_driver',
  value             => 'neutron.scheduler.dhcp_agent_scheduler.WeightScheduler',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
  notify            => Service['neutron-server'],
}

# configure /etc/keystone/keystone.conf
ini_setting { "keystone.conf notification driver":
  ensure            => present,
  path              => '/etc/keystone/keystone.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
  notify            => Service['keystone'],
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
#ini_setting { "ml2 extension_drivers":
#  ensure            => present,
#  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
#  section           => 'ml2',
#  key_val_separator => '=',
#  setting           => 'extension_drivers',
#  value             => 'port_security',
#  notify            => Service['neutron-server'],
#}
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
ini_setting { "ml2 restproxy neutron_id":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'neutron_id',
  value             => '%(neutron_id)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy keystone_auth_url":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auth_url',
  value             => '%(keystone_auth_url)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy keystone_auth_user":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auth_user',
  value             => '%(keystone_auth_user)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy keystone_password":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auth_password',
  value             => '%(keystone_password)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy keystone_auth_tenant":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auth_tenant',
  value             => '%(keystone_auth_tenant)s',
  notify            => Service['neutron-server'],
}

# change ml2 ownership
file { '/etc/neutron/plugins/ml2':
  owner   => neutron,
  group   => neutron,
  recurse => true,
  notify  => Service['neutron-server'],
}

service { 'neutron-server':
  ensure  => running,
  enable  => true,
}
service { 'keystone':
  ensure  => running,
  enable  => true,
}
service { 'neutron-dhcp-agent':
  ensure  => stopped,
  enable  => false,
}
service { 'neutron-metadata-agent':
  ensure  => stopped,
  enable  => false,
}
#service {'neutron-bsn-agent':
#  ensure  => stopped,
#  enable  => false,
#}



