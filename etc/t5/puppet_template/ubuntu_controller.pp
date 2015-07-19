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

# neutron settings
$neutron_conf_path = "/etc/neutron/plugins/ml2/ml2_conf.ini"

if ($operatingsystem == 'Ubuntu') and ($operatingsystemrelease =~ /^14.*/) {
    $neutron_ovs_conf_path = "/etc/neutron/plugins/ml2/ml2_conf.ini"
} else {
    $neutron_ovs_conf_path = "/etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini"
}
$neutron_base_conf_path = "/etc/neutron/neutron.conf"
$neutron_l3_conf_path = '/etc/neutron/l3_agent.ini'
$neutron_dhcp_conf_path = '/etc/neutron/dhcp_agent.ini'
$neutron_main_conf_path = "/etc/neutron/neutron.conf"
$bigswitch_ssl_cert_directory = '/etc/neutron/plugins/ml2/ssl'


# stop neutron server and start it only if there is an SQL connection string defined
exec{"neutronserverrestart":
    refreshonly => true,
    command => 'bash -c \'grep -R "connection\s*=" /etc/neutron/* | grep -v "#" && service neutron-server restart || service neutron-server stop ||:\'',
    path    => $binpath,
}
if $operatingsystem == 'Ubuntu' {
  $restart_nagent_comm = "service neutron-plugin-openvswitch-agent restart ||:;"
}
if $operatingsystem == 'CentOS' {
  # the old version of centos openvswitch version had issues after the bond changes and required a restart as well
  $restart_nagent_comm = "/etc/init.d/openvswitch restart ||:; /etc/init.d/neutron-openvswitch-agent restart ||:;"
}
if $operatingsystem == 'RedHat' {
  $restart_nagent_comm = "service neutron-openvswitch-agent restart ||:;"
}

# main restart event triggered by all ini setting changes and file contents changes.
# Restarts the rest of the openstack services as well
exec{"restartneutronservices":
    refreshonly => $neutron_restart_refresh_only,
    command => $restart_nagent_comm,
    notify => [Exec['checkagent'], Exec['neutrondhcprestart'], Exec['neutronl3restart'], Exec['neutronserverrestart'], Exec['neutronmetarestart'], Exec['restartnovaservices'], Exec['ensurecoroclone']],
    path    => $binpath,
}

# this is an additional check to make sure the openvswitch-agent is running. it
# was necessary on older versions of redhat because the agent would fail to
# restart the first time while all of the other services were being restarted.
# it may no longer be necessary on RHEL 7
exec{"checkagent":
    refreshonly => true,
    command => "[ $(ps -ef | grep openvswitch-agent | wc -l) -eq 0 ] && service neutron-openvswitch-agent restart ||:;",
    path    => $binpath,
}
exec{"neutronl3restart":
    refreshonly => true,
    command => "service neutron-l3-agent restart ||:;",
    path    => $binpath,
}
exec{"neutronmetarestart":
    refreshonly => true,
    command => "service neutron-metadata-agent restart ||:;",
    path    => $binpath,
}
exec{"neutrondhcprestart":
    refreshonly => true,
    command => "service neutron-dhcp-agent restart ||:;",
    path    => $binpath,
}

# several other openstack services to restart since we interrupt network connectivity.
# this is done asynchronously with the & operator and we only wait 5 seconds before continuing.
$nova_services = 'nova-conductor nova-cert nova-consoleauth nova-scheduler nova-compute apache2 httpd'
exec{"restartnovaservices":
    refreshonly=> true,
    command => "bash -c 'for s in ${nova_services}; do (sudo service \$s restart &); (sudo service openstack-\$s restart &); echo \$s; done; sleep 5'",
    path    => $binpath
}

# this configures coroclone on systems where it is available (Fuel) to allow
# the dhcp agent and l3 agent to run on multiple nodes.
exec{'ensurecoroclone':
    refreshonly=> true,
    command => 'bash -c \'crm configure clone clone_p_neutron-dhcp-agent p_neutron-dhcp-agent meta interleave="true" is-managed="true" target-role="Started"; crm configure clone clone_p_neutron-l3-agent p_neutron-l3-agent meta interleave="true" is-managed="true" target-role="Started"; echo 1\'',
    path    => $binpath
}

# basic conf directories
$conf_dirs = ["/etc/neutron/plugins/ml2"]
file {$conf_dirs:
    ensure => "directory",
    owner => "neutron",
    group => "neutron",
    mode => 755,
    require => Exec['ensureovsagentconfig']
}

# ovs agent file may not be present, if so link to main conf so this script can
# modify the same thing
exec{'ensureovsagentconfig':
    command => "bash -c 'mkdir -p /etc/neutron/plugins/openvswitch/; ln -s /etc/neutron/neutron.conf $neutron_ovs_conf_path; echo 0'",
    path => $binpath
}


# make sure the head conf directory exists before we try to set an ini value in
# it below. This can probably be replaced with a 'file' type
exec{"heatconfexists":
    command => "bash -c 'mkdir /etc/heat/; touch /etc/heat/heat.conf; echo done'",
    path    => $binpath
}

# use password for deferred authentication method for heat
# so users don't need extra roles to use heat. with this method it just uses
# the user's current token so it's not good for long lived templates that could
# take longer to setup than the token lasts, but its fine for our network
# templates because they always finish within seconds.
ini_setting {"heat_deferred_auth_method":
  path => '/etc/heat/heat.conf',
  section  => 'DEFAULT',
  setting => 'deferred_auth_method',
  value => 'password',
  ensure => present,
  notify => Exec['restartheatservices'],
  require => Exec['heatconfexists']
}
$heat_services = 'heat-api heat-engine heat-api-cfn'
exec{"restartheatservices":
    refreshonly=> true,
    command => "bash -c 'for s in ${heat_services}; do (sudo service \$s restart &); (sudo service openstack-\$s restart &); echo \$s; done; sleep 5'",
    path    => $binpath
}


# reference ml2 ini from init script
file{'neutron_init_config':
  ensure => file,
  mode   => 0644,
  path   => '/etc/default/neutron-server',
  content =>"NEUTRON_PLUGIN_CONFIG='${neutron_conf_path}'\n",
  notify => Exec['restartneutronservices'],
}


file { 'ssl_dir':
  ensure => "directory",
  path   => $bigswitch_ssl_cert_directory,
  owner  => "neutron",
  group  => "neutron",
  purge => true,
  recurse => true,
  mode   => 0750,
  notify => Exec['neutronserverrestart'],
}

if $operatingsystem == 'Ubuntu'{
    file {'keystone':
      path   => '/usr/lib/python2.7/dist-packages/keystone-signing',
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => 0777,
      notify => Exec['restartneutronservices'],
    }
}
if ($operatingsystem == 'CentOS') and ($operatingsystemrelease =~ /^6.*/) {
    file {'keystone26':
      path   => '/usr/lib/python2.6/site-packages/keystone-signing',
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => 0777,
      notify => Exec['restartneutronservices'],
    }
}

$MYSQL_USER='cat /etc/neutron/neutron.conf | grep "mysql://" | grep -v "#" | awk -F "//" \'{ print $2 }\' | awk -F ":" \'{ print $1 }\''
$MYSQL_PASS='cat /etc/neutron/neutron.conf | grep "mysql://" | grep -v "#" | awk -F "//" \'{ print $2 }\' | awk -F ":" \'{ print $2 }\' | awk -F "@" \'{ print $1 }\''
$MYSQL_HOST='cat /etc/neutron/neutron.conf | grep "mysql://" | grep -v "#" | awk -F "//" \'{ print $2 }\' | awk -F "@" \'{ print $2 }\' | awk -F "/" \'{ print $1 }\' | awk -F ":" \'{ print $1 }\''
$MYSQL_DB='cat /etc/neutron/neutron.conf | grep "mysql://" | grep -v "#" | awk -F "//" \'{ print $2 }\' | awk -F "@" \'{ print $2 }\' | awk -F "/" \'{ print $2 }\' | awk -F "?" \'{ print $1 }\''
$MYSQL_COM="mysql -u `$MYSQL_USER` -p`$MYSQL_PASS` -h `$MYSQL_HOST` `$MYSQL_DB`"
exec {"cleanup_neutron":
  onlyif => ["which mysql", "echo 'show tables' | $MYSQL_COM"],
  path => $binpath,
  command => "echo 'delete ports, floatingips from ports INNER JOIN floatingips on floatingips.floating_port_id = ports.id where ports.network_id NOT IN (select network_id from ml2_network_segments where network_type=\"vlan\");' | $MYSQL_COM;
              echo 'delete ports, routers from ports INNER JOIN routers on routers.gw_port_id = ports.id where ports.network_id NOT IN (select network_id from ml2_network_segments where network_type=\"vlan\");' | $MYSQL_COM;
              echo 'delete from ports where network_id NOT in (select network_id from ml2_network_segments where network_type=\"vlan\");' | $MYSQL_COM;
              echo 'delete from subnets where network_id NOT IN (select network_id from ml2_network_segments where network_type=\"vlan\");' | $MYSQL_COM;
              echo 'delete from networks where id NOT IN (select network_id from ml2_network_segments where network_type=\"vlan\");' | $MYSQL_COM;
              echo 'delete from ports where network_id NOT IN (select network_id from networks);' | $MYSQL_COM;
              echo 'delete from routers where gw_port_id NOT IN (select id from ports);' | $MYSQL_COM;
              echo 'delete from floatingips where floating_port_id NOT IN (select id from ports);' | $MYSQL_COM;
              echo 'delete from floatingips where fixed_port_id NOT IN (select id from ports);' | $MYSQL_COM;
              echo 'delete from subnets where network_id NOT IN (select id from networks);' | $MYSQL_COM;
             "
}
if $operatingsystem == 'CentOS' or $operatingsystem == 'RedHat'{
    file{'selinux_allow_certs':
       ensure => file,
       mode => 0644,
       path => '/root/neutroncerts.te',
       content => '
module neutroncerts 1.0;

require {
        type neutron_t;
        type etc_t;
        class dir create;
        class file create;
}

#============= neutron_t ==============
allow neutron_t etc_t:dir create;
allow neutron_t etc_t:file create;
',
       notify => Exec["selinuxcompile"],
    }
    exec {"selinuxcompile":
       refreshonly => true,
       command => "bash -c 'semanage permissive -a neutron_t;
                   checkmodule -M -m -o /root/neutroncerts.mod /root/neutroncerts.te;
                   semodule_package -m /root/neutroncerts.mod -o /root/neutroncerts.pp;
                   semodule -i /root/neutroncerts.pp' ||:",
        path    => $binpath,
    }
}


# bond lldp settings
exec {"loadbond":
   command => 'modprobe bonding',
   path    => $binpath,
   unless => "lsmod | grep bonding",
   notify => Exec['deleteovsbond'],
}
exec {"deleteovsbond":
  command => "bash -c 'for int in \$(/usr/bin/ovs-appctl bond/list | grep -v slaves | grep \"${bond_int0}\" | awk -F '\"' ' '{ print \$1 }'\"'); do ovs-vsctl --if-exists del-port \$int; done'",
  path    => $binpath,
  require => Exec['lldpdinstall'],
  onlyif  => "/sbin/ifconfig ${phy_bridge} && ovs-vsctl show | grep '\"${bond_int0}\"'",
  notify => Exec['networkingrestart']
}
exec {"clearint0":
  command => "ovs-vsctl --if-exists del-port $bond_int0",
  path    => $binpath,
  require => Exec['lldpdinstall'],
  onlyif => "ovs-vsctl show | grep 'Port \"${bond_int0}\"'",
}
exec {"clearint1":
  command => "ovs-vsctl --if-exists del-port $bond_int1",
  path    => $binpath,
  require => Exec['lldpdinstall'],
  onlyif => "ovs-vsctl show | grep 'Port \"${bond_int1}\"'",
}

# make sure bond module is loaded
if $operatingsystem == 'Ubuntu' {
    file_line { 'bond':
       path => '/etc/modules',
       line => 'bonding',
       notify => Exec['loadbond'],
    }
    file_line { 'includebond':
       path => '/etc/network/interfaces',
       line => 'source /etc/network/interfaces.d/*',
       notify => Exec['loadbond'],
    }
    file {'bondmembers':
        ensure => file,
        path => '/etc/network/interfaces.d/bond',
        mode => 0644,
        content => "
auto ${bond_int0}
iface ${bond_int0} inet manual
bond-master bond0

auto ${bond_int1}
iface ${bond_int1} inet manual
bond-master bond0

auto bond0
    iface bond0 inet manual
    address 0.0.0.0
    bond-mode ${bond_mode}
    bond-xmit_hash_policy 1
    bond-miimon 50
    bond-updelay ${bond_updelay}
    bond-slaves none
    ",
    }
    exec {"networkingrestart":
       refreshonly => true,
       require => [Exec['loadbond'], File['bondmembers'], Exec['deleteovsbond'], Exec['lldpdinstall']],
       command => "bash -c '
         sed -i s/auto bond0//g /etc/network/interfaces
         sed -i s/iface bond0/iface bond0old/g /etc/network/interfaces
         # 1404+ doesnt allow init script full network restart
         if [[ \$(lsb_release -r | tr -d -c 0-9) = 14* ]]; then
             ifdown ${bond_int0}
             ifdown ${bond_int1}
             ifdown bond0
             ifup ${bond_int0} &
             ifup ${bond_int1} &
             ifup bond0 &
         else
             /etc/init.d/networking restart
         fi'",
       notify => Exec['addbondtobridge'],
       path    => $binpath,
    }
    if ! $offline_mode {
        exec{"lldpdinstall":
            command => 'bash -c \'
              # default to 12.04
              export urelease=12.04;
              [ "$(lsb_release -r | tr -d -c 0-9)" = "1410" ] && export urelease=14.10;
              [ "$(lsb_release -r | tr -d -c 0-9)" = "1404" ] && export urelease=14.04;
              wget "http://download.opensuse.org/repositories/home:vbernat/xUbuntu_$urelease/Release.key";
              sudo apt-key add - < Release.key;
              echo "deb http://download.opensuse.org/repositories/home:/vbernat/xUbuntu_$urelease/ /"\
                  > /etc/apt/sources.list.d/lldpd.list;
              rm /var/lib/dpkg/lock ||:; rm /var/lib/apt/lists/lock ||:; apt-get update;
              apt-get -o Dpkg::Options::=--force-confdef install --allow-unauthenticated -y lldpd;
              if [[ $(lsb_release -r | tr -d -c 0-9) = 14* ]]; then
                  apt-get install -y ifenslave-2.6
              fi\'',
            path    => $binpath,
            notify => [Exec['networkingrestart'], File['ubuntulldpdconfig']],
        }
    } else {
        exec{"lldpdinstall":
            onlyif => "bash -c '! ls /etc/init.d/lldpd'",
            command => "echo noop",
            path    => $binpath,
            notify => [Exec['networkingrestart'], File['ubuntulldpdconfig']],
        }
    }
    exec{"triggerinstall":
        onlyif => 'bash -c "! ls /etc/init.d/lldpd"',
        command => 'echo',
        notify => Exec['lldpdinstall'],
        path    => $binpath,
    }
    file{'ubuntulldpdconfig':
        ensure => file,
        mode   => 0644,
        path   => '/etc/default/lldpd',
        content => "DAEMON_ARGS='-S 5c:16:c7:00:00:00 -I ${bond_interfaces} -L /usr/bin/lldpclinamewrap'\n",
        notify => Exec['lldpdrestart'],
    }
    exec {"openvswitchrestart":
       refreshonly => true,
       command => '/etc/init.d/openvswitch-switch restart',
       path    => $binpath,
    }
}
file{"lldlcliwrapper":
    ensure => file,
    mode   => 0755,
    path   => '/usr/bin/lldpclinamewrap',
    content =>"#!/bin/bash
# this script forces lldpd to use the same hostname that openstack uses
(sleep 2 && echo \"configure system hostname ${lldp_advertised_name}\" | lldpcli &)
lldpcli \$@
",
    notify => Exec['lldpdrestart'],
}
if $operatingsystem == 'RedHat' {
    if ! $offline_mode {
        exec {'lldpdinstall':
           onlyif => "yum --version && (! ls /etc/init.d/lldpd)",
           command => 'bash -c \'
               export baseurl="http://download.opensuse.org/repositories/home:/vbernat/";
               [[ $(cat /etc/redhat-release | tr -d -c 0-9) =~ ^6 ]] && export url="${baseurl}/RedHat_RHEL-6/x86_64/lldpd-0.7.14-1.1.x86_64.rpm";
               [[ $(cat /etc/redhat-release | tr -d -c 0-9) =~ ^7 ]] && export url="${baseurl}/RHEL_7/x86_64/lldpd-0.7.14-1.1.x86_64.rpm";
               cd /root/;
               wget "$url" -O lldpd.rpm;
               rpm -i lldpd.rpm\'',
           path    => $binpath,
           notify => File['redhatlldpdconfig'],
        }
    } else {
        exec {'lldpdinstall':
           onlyif => "bash -c '! ls /etc/init.d/lldpd'",
           command => "echo noop",
           path    => $binpath,
           notify => File['redhatlldpdconfig'],
        }
    }
    file{'redhatlldpdconfig':
        ensure => file,
        mode   => 0644,
        path   => '/etc/sysconfig/lldpd',
        content => "LLDPD_OPTIONS='-S 5c:16:c7:00:00:00 -I ${bond_interfaces} -L /usr/bin/lldpclinamewrap'\n",
        notify => Exec['lldpdrestart'],
    }
    ini_setting{"neutron_service":
        path => "/usr/lib/systemd/system/neutron-server.service",
        section => "Service",
        setting => "Type",
        value => "simple",
        ensure => present,
        notify => Exec['reloadservicedef']
    }
    exec{"reloadservicedef":
        refreshonly => true,
        command => "systemctl daemon-reload",
        path    => $binpath,
        notify => Exec['restartneutronservices']
    }
    exec {"networkingrestart":
       refreshonly => true,
       command => '/etc/init.d/network restart',
       require => [Exec['loadbond'], File['bondmembers'], Exec['deleteovsbond']],
       notify => Exec['addbondtobridge'],
    }
    file{'bondmembers':
        require => [Exec['loadbond']],
        ensure => file,
        mode => 0644,
        path => '/etc/sysconfig/network-scripts/ifcfg-bond0',
        content => "
DEVICE=bond0
USERCTL=no
BOOTPROTO=none
ONBOOT=yes
BONDING_OPTS='mode=${bond_mode} miimon=50 updelay=${bond_updelay} xmit_hash_policy=1'
",
    }
    file{'bond_int0config':
        require => File['bondmembers'],
        notify => Exec['networkingrestart'],
        ensure => file,
        mode => 0644,
        path => "/etc/sysconfig/network-scripts/ifcfg-$bond_int0",
        content => "DEVICE=$bond_int0\nMASTER=bond0\nSLAVE=yes\nONBOOT=yes\nUSERCTL=no\n",
    }
    if $bond_int0 != $bond_int1 {
        file{'bond_int1config':
            require => File['bondmembers'],
            notify => Exec['networkingrestart'],
            ensure => file,
            mode => 0644,
            path => "/etc/sysconfig/network-scripts/ifcfg-$bond_int1",
            content => "DEVICE=$bond_int1\nMASTER=bond0\nSLAVE=yes\nONBOOT=yes\nUSERCTL=no\n",
        }
    }

    exec {"openvswitchrestart":
       refreshonly => true,
       command => 'service openvswitch restart',
       path    => $binpath,
    }

}
if $operatingsystem == 'CentOS' {
    if ! $offline_mode {
        exec {'lldpdinstall':
           onlyif => "yum --version && (! ls /etc/init.d/lldpd)",
           command => 'bash -c \'
               export baseurl="http://download.opensuse.org/repositories/home:/vbernat/";
               [[ $(cat /etc/redhat-release | tr -d -c 0-9) =~ ^6 ]] && export url="${baseurl}/CentOS_CentOS-6/x86_64/lldpd-0.7.14-1.1.x86_64.rpm";
               [[ $(cat /etc/redhat-release | tr -d -c 0-9) =~ ^7 ]] && export url="${baseurl}/CentOS_7/x86_64/lldpd-0.7.14-1.1.x86_64.rpm";
               cd /root/;
               wget "$url" -O lldpd.rpm;
               rpm -i lldpd.rpm\'',
           path    => $binpath,
           notify => File['centoslldpdconfig'],
        }
    } else {
        exec {'lldpdinstall':
           onlyif => "bash -c '! ls /etc/init.d/lldpd'",
           command => "echo noop",
           path    => $binpath,
           notify => File['centoslldpdconfig'],
        }
    }
    file{'centoslldpdconfig':
        ensure => file,
        mode   => 0644,
        path   => '/etc/sysconfig/lldpd',
        content => "LLDPD_OPTIONS='-S 5c:16:c7:00:00:00 -I ${bond_interfaces} -L /usr/bin/lldpclinamewrap'\n",
        notify => Exec['lldpdrestart'],
    }
    exec {"networkingrestart":
       refreshonly => true,
       command => '/etc/init.d/network restart',
       require => [Exec['loadbond'], File['bondmembers'], Exec['deleteovsbond'], Exec['lldpdinstall']],
       notify => Exec['addbondtobridge'],
    }
    file{'bondmembers':
        require => [Exec['lldpdinstall'],Exec['loadbond'],File['centoslldpdconfig']],
        ensure => file,
        mode => 0644,
        path => '/etc/sysconfig/network-scripts/ifcfg-bond0',
        content => "
DEVICE=bond0
USERCTL=no
BOOTPROTO=none
ONBOOT=yes
BONDING_OPTS='mode=${bond_mode} miimon=50 updelay=${bond_updelay} xmit_hash_policy=1'
",
    }
    file{'bond_int0config':
        require => File['bondmembers'],
        notify => Exec['networkingrestart'],
        ensure => file,
        mode => 0644,
        path => "/etc/sysconfig/network-scripts/ifcfg-$bond_int0",
        content => "DEVICE=$bond_int0\nMASTER=bond0\nSLAVE=yes\nONBOOT=yes\nUSERCTL=no\n",
    }
    if $bond_int0 != $bond_int1 {
        file{'bond_int1config':
            require => File['bondmembers'],
            notify => Exec['networkingrestart'],
            ensure => file,
            mode => 0644,
            path => "/etc/sysconfig/network-scripts/ifcfg-$bond_int1",
            content => "DEVICE=$bond_int1\nMASTER=bond0\nSLAVE=yes\nONBOOT=yes\nUSERCTL=no\n",
        }
    }
    exec {"openvswitchrestart":
       refreshonly => true,
       command => '/etc/init.d/openvswitch restart',
       path    => $binpath,
    }
}
exec {"ensurebridge":
  command => "ovs-vsctl --may-exist add-br ${phy_bridge}",
  path    => $binpath,
}
exec {"addbondtobridge":
   command => "ovs-vsctl --may-exist add-port ${phy_bridge} bond0",
   onlyif => "/sbin/ifconfig bond0 && ! ovs-ofctl show ${phy_bridge} | grep '(bond0)'",
   path    => $binpath,
   notify => Exec['openvswitchrestart'],
   require => Exec['ensurebridge'],
}
exec{'lldpdrestart':
    refreshonly => true,
    require => Exec['lldpdinstall'],
    command => "rm /var/run/lldpd.socket ||:;/etc/init.d/lldpd restart",
    path    => $binpath,
}
file{'lldpclioptions':
    ensure => file,
    mode   => 0644,
    path   => '/etc/lldpd.conf',
    content => "configure lldp tx-interval ${lldp_transmit_interval}",
    notify => Exec['lldpdrestart'],
}

