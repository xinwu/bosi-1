$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"
$uplinks = [%(uplinks)s]

# install selinux policies
$selinux_enabled = generate('/bin/sh', '-c', "sestatus | grep 'enabled' | tr -d '\n'")
if $selinux_enabled {
    Package { allow_virtual => true }
    class { selinux:
      mode => '%(selinux_mode)s',
    }
    selinux::module { 'selinux-bcf':
      ensure => 'present',
      source => 'puppet:///modules/selinux/centos.te',
    }
}

# comment out heat domain related configurations
$heat_config = file('/etc/heat/heat.conf','/dev/null')
if($heat_config != '') {
    ini_setting { "heat paste":
        ensure            => present,
        path              => '/etc/heat/heat.conf',
        section           => 'paste_deploy',
        key_val_separator => '=',
        setting           => 'api_paste_config',
        value             => '/usr/share/heat/api-paste-dist.ini',
    }
    ini_setting { "heat debug":
        ensure            => present,
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'debug',
        value             => 'True',
        notify            => Service['openstack-heat-engine'],
    }
    #ini_setting { "heat stack_domain_admin_password":
    #    ensure            => absent,
    #    path              => '/etc/heat/heat.conf',
    #    section           => 'DEFAULT',
    #    key_val_separator => '=',
    #    setting           => 'stack_domain_admin_password',
    #    notify            => Service['openstack-heat-engine'],
    #}
    #ini_setting { "heat stack_domain_admin":
    #    ensure            => absent,
    #    path              => '/etc/heat/heat.conf',
    #    section           => 'DEFAULT',
    #    key_val_separator => '=',
    #    setting           => 'stack_domain_admin',
    #    notify            => Service['openstack-heat-engine'],
    #}
    #ini_setting { "heat stack_user_domain":
    #    ensure            => absent,
    #    path              => '/etc/heat/heat.conf',
    #    section           => 'DEFAULT',
    #    key_val_separator => '=',
    #    setting           => 'stack_user_domain',
    #    notify            => Service['openstack-heat-engine'],
    #}
    ini_setting {"heat_deferred_auth_method":
        path              => '/etc/heat/heat.conf',
        section           => 'DEFAULT',
        setting           => 'deferred_auth_method',
        value             => 'password',
        ensure            => present,
        notify            => Service['openstack-heat-engine'],
    }
    service { 'openstack-heat-engine':
        ensure            => running,
        enable            => true,
        path              => $binpath,
    }
}

# uplink mtu
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
file_line { "touch /var/lock/subsys/local":
    path    => '/etc/rc.d/rc.local',
    line    => "touch /var/lock/subsys/local",
}

# make sure known_hosts is cleaned up
file { "/root/.ssh/known_hosts":
    ensure => absent,
}

# glance paste config
ini_setting { "glance-api filesystem_store_datadir":
    ensure            => present,
    path              => '/etc/glance/glance-api.conf',
    section           => 'glance_store',
    key_val_separator => '=',
    setting           => 'filesystem_store_datadir',
    value             => '/var/lib/glance/images/',
}
ini_setting { "glance-api paste config":
    ensure            => present,
    path              => '/etc/glance/glance-api.conf',
    section           => 'paste_deploy',
    key_val_separator => '=',
    setting           => 'config_file',
    value             => '/usr/share/glance/glance-api-dist-paste.ini',
}
ini_setting { "glance-registry paste config":
    ensure            => present,
    path              => '/etc/glance/glance-registry.conf',
    section           => 'paste_deploy',
    key_val_separator => '=',
    setting           => 'config_file',
    value             => '/usr/share/glance/glance-registry-dist-paste.ini',
}

# keystone paste config
ini_setting { "keystone paste config":
    ensure            => present,
    path              => '/etc/keystone/keystone.conf',
    section           => 'paste_deploy',
    key_val_separator => '=',
    setting           => 'config_file',
    value             => '/usr/share/keystone/keystone-dist-paste.ini',
}
ini_setting { "keystone.conf notification driver":
  ensure            => present,
  path              => '/etc/keystone/keystone.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
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
file {'/etc/sysconfig/modules/8021q.modules':
    ensure  => file,
    mode    => 0777,
    content => "modprobe 8021q",
}
exec { "load 8021q":
    command => "modprobe 8021q",
    path    => $binpath,
}

# disable neutron-bsn-agent service
#service {'neutron-bsn-agent':
#    ensure  => stopped,
#    enable  => false,
#    path    => $binpath,
#}

# purge bcf controller public key
exec { 'purge bcf key':
    command => "rm -rf /var/lib/neutron/host_certs/*",
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
  value             => 'router,bsn_service_plugin',
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
ini_setting { "neutron.conf allow_automatic_l3agent_failover":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'allow_automatic_l3agent_failover',
  value             => 'True',
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
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# disable l3 agent
service { 'neutron-l3-agent':
  ensure  => stopped,
  enable  => false,
  path    => $binpath,
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
ini_setting { "ml2 extension_drivers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'extension_drivers',
  value             => 'port-security',
  notify            => Service['neutron-server'],
}
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
  value             => 'openvswitch, bsn_ml2',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy ssl cert directory":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'ssl_cert_directory',
  value             => '/var/lib/neutron',
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

# make services in right state
service { 'neutron-server':
  ensure  => running,
  enable  => true,
  path    => $binpath,
  require => Exec['purge bcf key'],
}
service { 'neutron-dhcp-agent':
  ensure  => stopped,
  enable  => false,
  path    => $binpath,
}
service { 'neutron-metadata-agent':
  ensure  => stopped,
  enable  => false,
  path    => $binpath,
}

# patch for packstack nova
package { "device-mapper-libs":
  ensure => latest,
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
ini_setting { "clear tunnel types":
  ensure            => absent,
  path              => '/etc/neutron/plugins/ml2/openvswitch_agent.ini',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'tunnel_types',
  require           => File['/etc/neutron/plugins/ml2/openvswitch_agent.ini'],
  notify            => Service['neutron-openvswitch-agent'],
}
# ovs section for vlan settings
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
# stop neutron-ovs-agent
service { 'neutron-openvswitch-agent':
  ensure  => stopped,
  enable  => false,
}
