import constants as const
import socket


class Node(object):
    def __init__(self, node_config, env):
        self.dst_dir = const.DST_DIR
        self.bash_script_path = None
        self.puppet_script_path = None
        self.selinux_script_path = None
        self.ospurge_script_path = None
        self.dhcp_reschedule_script_path = None
        self.dhcp_agent_scheduler_dir = None
        self.log = const.LOG_FILE
        self.hostname = node_config['hostname']
        self.fqdn = node_config.get('fqdn')
        if not self.fqdn:
            try:
                self.fqdn = socket.gethostbyaddr(self.hostname)[0]
            except Exception:
                self.fqdn = self.hostname
        self.uname = node_config.get('uname')
        self.mac = node_config.get('mac')
        if self.mac:
            self.mac = self.mac.lower().strip()
        self.role = node_config['role'].lower()
        self.skip = node_config['skip']
        self.deploy_mode = node_config.get('deploy_mode')
        self.os = node_config['os'].lower()
        self.os_version = str(node_config['os_version']).split(".")[0]
        self.user = node_config.get('user')
        self.passwd = node_config.get('passwd')
        self.uplink_interfaces = node_config.get('uplink_interfaces')
        self.uplink_mtu = node_config.get('uplink_mtu')
        if not self.uplink_mtu:
            self.uplink_mtu = 1500
        self.install_ivs = node_config.get('install_ivs')
        self.install_bsnstacklib = node_config.get('install_bsnstacklib')
        self.install_all = node_config.get('install_all')
        self.deploy_dhcp_agent = node_config.get('deploy_dhcp_agent')
        self.deploy_l3_agent = node_config.get('deploy_l3_agent')
        self.bridges = node_config.get('bridges')
        self.br_bond = node_config.get('br_bond')
        self.bond = node_config.get('bond')

        self.pxe_interface = node_config.get('pxe_interface')
        self.br_fw_admin = node_config.get('br_fw_admin')
        self.br_fw_admin_address = node_config.get('br_fw_admin_address')
        self.tagged_intfs = node_config.get('tagged_intfs')
        self.ex_gw = node_config.get('ex_gw')
        self.tag = node_config.get('tag')
        self.env_tag = env.tag
        self.pip_proxy = env.pip_proxy
        if not env.pip_proxy:
            self.pip_proxy = "false"
        self.certificate_dir = env.certificate_dir
        self.upgrade_dir = env.upgrade_dir
        self.upgrade_pkgs = env.upgrade_pkgs
        self.cleanup = env.cleanup
        self.skip_ivs_version_check = env.skip_ivs_version_check
        self.rabbit_hosts = None

        # keystone client
        self.keystone_auth_url = None
        self.keystone_auth_user = None
        self.keystone_password = None
        self.keystone_auth_tenant = None

        # setup result
        self.time_diff = 0
        self.last_log = None

        # rhosp related config
        self.rhosp_automate_register = env.rhosp_automate_register
        self.rhosp_installer_management_interface = (
            env.rhosp_installer_management_interface)
        self.rhosp_installer_pxe_interface = env.rhosp_installer_pxe_interface
        self.rhosp_undercloud_dns = env.rhosp_undercloud_dns
        self.rhosp_register_username = env.rhosp_register_username
        self.rhosp_register_passwd = env.rhosp_register_passwd
        self.installer_pxe_interface_ip = env.installer_pxe_interface_ip

        self.neutron_id = env.neutron_id
        self.tenant_api_version = env.tenant_api_version
        self.openstack_release = env.openstack_release
        self.bsnstacklib_version_lower = env.bsnstacklib_version_lower
        self.bsnstacklib_version_upper = env.bsnstacklib_version_upper
        self.bcf_version = env.bcf_version
        self.bcf_controllers = env.bcf_controllers
        self.bcf_controller_ips = env.bcf_controller_ips
        self.bcf_controller_user = env.bcf_controller_user
        self.bcf_controller_passwd = env.bcf_controller_passwd
        self.bcf_openstack_management_tenant = (
            env.bcf_openstack_management_tenant)
        self.bcf_master = env.bcf_master
        self.physnet = env.physnet
        self.lower_vlan = env.lower_vlan
        self.upper_vlan = env.upper_vlan
        self.setup_node_ip = env.setup_node_ip
        self.setup_node_dir = env.setup_node_dir
        self.selinux_mode = env.selinux_mode
        self.fuel_cluster_id = env.fuel_cluster_id
        self.rhosp = env.rhosp
        self.ivs_pkg_map = env.ivs_pkg_map
        self.ivs_pkg = None
        self.ivs_debug_pkg = None
        self.ivs_version = None
        self.old_ivs_version = node_config.get('old_ivs_version')

        # in case of config env (packstack), bond and br_bond
        # may be empty
        if not self.br_bond:
            self.br_bond = const.T5_CENTOS_BOND_BRIDGE

        if not self.bond:
            self.bond = const.T5_CENTOS_BOND_NAME

        if self.os in const.RPM_OS_SET:
            self.ivs_pkg = self.ivs_pkg_map.get('rpm')
            self.ivs_debug_pkg = self.ivs_pkg_map.get('debug_rpm')
        elif self.os in const.DEB_OS_SET:
            self.ivs_pkg = self.ivs_pkg_map.get('deb')
            self.ivs_debug_pkg = self.ivs_pkg_map.get('debug_deb')
        self.error = node_config.get('error')

        # check os compatability
        if (((self.os == const.CENTOS) and
             (self.os_version not in const.CENTOS_VERSIONS))
            or ((self.os == const.UBUNTU) and
                (self.os_version not in const.UBUNTU_VERSIONS))
            or ((self.os == const.REDHAT) and
                (self.os_version not in const.REDHAT_VERSIONS))):
            self.skip = True
            self.error = (r'''%(os)s %(os_version)s is not supported''' %
                         {'os': self.os, 'os_version': self.os_version})

        # get ivs version
        if self.ivs_pkg:
            temp = []
            subs = self.ivs_pkg.split('-')
            for sub in subs:
                temp.extend(sub.split('_'))
            for i in range(len(temp)):
                if temp[i].lower() == 'ivs':
                    self.ivs_version = temp[i + 1]
                    break

        # check ivs compatability
        if self.deploy_mode == const.T6 and self.old_ivs_version:
            ivs_version_num = self.ivs_version.split('.')
            old_ivs_version_num = self.old_ivs_version.split('.')
            if not old_ivs_version_num[0].isdigit():
                return
            if old_ivs_version_num[0] == '0':
                return
            if str(self.ivs_version) in str(self.old_ivs_version):
                return
            if self.skip_ivs_version_check:
                return
            diff = int(ivs_version_num[0]) - int(old_ivs_version_num[0])
            if self.ivs_version < self.old_ivs_version:
                self.skip = True
                self.error = (r'''Existing ivs %(old_ivs_version)s is newer '''
                              '''than %(ivs_version)s''' %
                              {'old_ivs_version': self.old_ivs_version,
                               'ivs_version': self.ivs_version})
            elif diff > 1:
                self.skip = True
                self.error = (r'''Existing ivs %(old_ivs_version)s is '''
                              '''%(diff)d version behind %(ivs_version)s''' %
                              {'old_ivs_version': self.old_ivs_version,
                               'diff': diff,
                               'ivs_version': self.ivs_version})

    def set_bash_script_path(self, bash_script_path):
        self.bash_script_path = bash_script_path

    def set_puppet_script_path(self, puppet_script_path):
        self.puppet_script_path = puppet_script_path

    def set_selinux_script_path(self, selinux_script_path):
        self.selinux_script_path = selinux_script_path

    def set_ospurge_script_path(self, ospurge_script_path):
        self.ospurge_script_path = ospurge_script_path

    def set_dhcp_reschedule_script_path(self, dhcp_reschedule_script_path):
        self.dhcp_reschedule_script_path = dhcp_reschedule_script_path

    def set_dhcp_agent_scheduler_dir(self, dhcp_agent_scheduler_dir):
        self.dhcp_agent_scheduler_dir = dhcp_agent_scheduler_dir

    def set_time_diff(self, time_diff):
        self.time_diff = time_diff

    def set_last_log(self, last_log):
        self.last_log = last_log

    def set_rabbit_hosts(self, rabbit_hosts):
        self.rabbit_hosts = rabbit_hosts

    def set_keystone_auth_url(self, keystone_auth_url):
        self.keystone_auth_url = keystone_auth_url

    def set_keystone_auth_user(self, keystone_auth_user):
        self.keystone_auth_user = keystone_auth_user

    def set_keystone_password(self, keystone_password):
        self.keystone_password = keystone_password

    def set_keystone_auth_tenant(self, keystone_auth_tenant):
        self.keystone_auth_tenant = keystone_auth_tenant

    def get_network_vlan_ranges(self):
        return (r'''%(physnet)s:%(lower_vlan)s:%(upper_vlan)s''' %
               {'physnet': self.physnet,
                'lower_vlan': self.lower_vlan,
                'upper_vlan': self.upper_vlan})

    def get_bridge_mappings(self):
        return (r'''%(physnet)s:%(bond_bridge)s''' %
               {'physnet': self.physnet,
                'bond_bridge': self.br_bond})

    def get_uplink_intfs_for_ivs(self):
        uplink_intfs = []
        for intf in self.uplink_interfaces:
            uplink_intfs.append(' -u ')
            uplink_intfs.append(intf)
        return ''.join(uplink_intfs)

    def get_ivs_internal_ports(self):
        internal_ports = []
        if self.bridges:
            for br in self.bridges:
                if (not br.br_vlan) or (br.br_key == const.BR_KEY_PRIVATE):
                    continue
                prefixes = br.br_key.split('/')
                segment = prefixes[len(prefixes) - 1]
                port_prefix = const.IVS_INTERNAL_PORT_DIC.get(segment)
                if not port_prefix:
                    continue
                port = "%s%s" % (port_prefix, self.fuel_cluster_id)
                internal_ports.append(' --internal-port=')
                internal_ports.append(port)
        return ''.join(internal_ports)

    def get_ivs_internal_port_ips(self):
        port_ips = []
        if not self.bridges:
            return ' '.join(port_ips)
        for br in self.bridges:
            if ((not br.br_vlan) or (not br.br_ip) or
                    (br.br_key == const.BR_KEY_PRIVATE)):
                continue
            prefixes = br.br_key.split('/')
            segment = prefixes[len(prefixes) - 1]
            port_prefix = const.IVS_INTERNAL_PORT_DIC.get(segment)
            if not port_prefix:
                continue
            port = "%s%s" % (port_prefix, self.fuel_cluster_id)
            port_ips.append(r'''"%(port)s,%(ip)s"''' %
                           {'port': port,
                            'ip': br.br_ip})
        return ",".join(port_ips)

    def get_all_ovs_brs(self):
        ovs_brs = set()
        # ovs_brs.add(r'''"%(br)s"''' % {'br': const.BR_NAME_INT})
        if self.bridges:
            for br in self.bridges:
                ovs_brs.add(r'''"%(br)s"''' % {'br': br.br_name})
            ovs_brs.add(r'''"%(br)s"''' % {'br': self.br_bond})
        return ' '.join(ovs_brs)

    def get_all_interfaces(self):
        interfaces = []
        if self.pxe_interface:
            interfaces.append(self.pxe_interface)
        if self.uplink_interfaces:
            for intf in self.uplink_interfaces:
                interfaces.append(intf)
        if self.tagged_intfs:
            for intf in self.tagged_intfs:
                interfaces.append(intf)
        return ' '.join(interfaces)

    def get_all_uplinks(self):
        uplinks = []
        for intf in self.uplink_interfaces:
            uplinks.append(intf)
        return ' '.join(uplinks)

    def get_comma_separated_uplinks(self):
        uplinks = []
        for intf in self.uplink_interfaces:
            uplinks.append(intf)
        return ','.join(uplinks)

    def get_all_bonds(self):
        bonds = set()
        if self.bond and self.bridges:
            for br in self.bridges:
                if (br.br_vlan) and (':' not in str(br.br_vlan)):
                    bonds.add(r'''%(bond)s.%(vlan)s''' %
                              {'bond': self.bond,
                               'vlan': br.br_vlan})
            bonds.add(r'''%(bond)s''' % {'bond': self.bond})
        return ' '.join(bonds)

    def get_default_gw(self):
        if self.ex_gw:
            return self.ex_gw
        else:
            return self.installer_pxe_interface_ip

    def get_controllers_for_neutron(self):
        return ','.join(self.bcf_controllers)

    def get_neutron_id(self):
        if self.neutron_id and self.fuel_cluster_id:
            return "%s-%s" % (self.neutron_id, str(self.fuel_cluster_id))
        elif self.fuel_cluster_id:
            return "neutron-%s" % str(self.fuel_cluster_id)
        return self.neutron_id

    def get_bsnstacklib_version_lower(self):
        return self.bsnstacklib_version_lower

    def get_bsnstacklib_version_upper(self):
        return self.bsnstacklib_version_upper

    def __str__(self):
        return (
            r'''
            dst_dir: %(dst_dir)s,
            bash_script_path: %(bash_script_path)s,
            puppet_script_path: %(puppet_script_path)s,
            selinux_script_path: %(selinux_script_path)s,
            ospurge_script_path: %(ospurge_script_path)s,
            dhcp_reschedule_script_path: %(dhcp_reschedule_script_path)s,
            dhcp_agent_scheduler_dir: %(dhcp_agent_scheduler_dir)s,
            log: %(log)s,
            hostname: %(hostname)s,
            fqdn: %(fqdn)s,
            uname: %(uname)s,
            mac: %(mac)s,
            role: %(role)s,
            skip: %(skip)s,
            deploy_mode: %(deploy_mode)s,
            os: %(os)s,
            os_version: %(os_version)s,
            user: %(user)s,
            passwd: %(passwd)s,
            uplink_interfaces: %(uplink_interfaces)s,
            uplink_mtu: %(uplink_mtu)s,
            install_ivs: %(install_ivs)s,
            install_bsnstacklib: %(install_bsnstacklib)s,
            install_all: %(install_all)s,
            deploy_dhcp_agent: %(deploy_dhcp_agent)s,
            deploy_l3_agent: %(deploy_l3_agent)s,
            bridges: %(bridges)s,
            br_bond: %(br_bond)s,
            bond: %(bond)s,
            pxe_interface: %(pxe_interface)s,
            br_fw_admin: %(br_fw_admin)s,
            br_fw_admin_address: %(br_fw_admin_address)s,
            tagged_intfs: %(tagged_intfs)s,
            ex_gw: %(ex_gw)s,
            tag: %(tag)s,
            env_tag: %(env_tag)s,
            pip_proxy: %(pip_proxy)s,
            certificate_dir: %(certificate_dir)s,
            upgrade_dir: %(upgrade_dir)s,
            upgrade_pkgs: %(upgrade_pkgs)s,
            cleanup: %(cleanup)s,
            rabbit_hosts: %(rabbit_hosts)s,
            keystone_auth_url: %(keystone_auth_url)s,
            keystone_auth_user: %(keystone_auth_user)s,
            keystone_password: %(keystone_password)s,
            keystone_auth_tenant: %(keystone_auth_tenant)s,
            time_diff: %(time_diff)s,
            last_log: %(last_log)s,
            rhosp_automate_register: %(rhosp_automate_register)s,
            rhosp_installer_management_interface:
            %(rhosp_installer_management_interface)s,
            rhosp_installer_pxe_interface:
            %(rhosp_installer_pxe_interface)s,
            rhosp_undercloud_dns: %(rhosp_undercloud_dns)s,
            rhosp_register_username: %(rhosp_register_username)s,
            rhosp_register_passwd: %(rhosp_register_passwd)s,
            installer_pxe_interface_ip: %(installer_pxe_interface_ip)s,
            neutron_id: %(neutron_id)s,
            tenant_api_version: %(tenant_api_version)s,
            openstack_release: %(openstack_release)s,
            bsnstacklib_version_lower: %(bsnstacklib_version_lower)s,
            bsnstacklib_version_upper: %(bsnstacklib_version_upper)s,
            bcf_version: %(bcf_version)s,
            bcf_controllers: %(bcf_controllers)s,
            bcf_controller_ips: %(bcf_controller_ips)s,
            bcf_controller_user: %(bcf_controller_user)s,
            bcf_controller_passwd: %(bcf_controller_passwd)s,
            bcf_openstack_management_tenant:
            %(bcf_openstack_management_tenant)s,
            bcf_master: %(bcf_master)s,
            physnet: %(physnet)s,
            lower_vlan: %(lower_vlan)s,
            upper_vlan: %(upper_vlan)s,
            setup_node_ip: %(setup_node_ip)s,
            setup_node_dir: %(setup_node_dir)s,
            selinux_mode: %(selinux_mode)s,
            fuel_cluster_id: %(fuel_cluster_id)s,
            rhosp: %(rhosp)s,
            ivs_pkg: %(ivs_pkg)s,
            ivs_debug_pkg: %(ivs_debug_pkg)s,
            ivs_version: %(ivs_version)s,
            old_ivs_version: %(old_ivs_version)s,
            error: %(error)s,
            ''' %
            {'dst_dir': self.dst_dir,
            'bash_script_path': self.bash_script_path,
            'puppet_script_path': self.puppet_script_path,
            'selinux_script_path': self.selinux_script_path,
            'ospurge_script_path': self.ospurge_script_path,
            'dhcp_reschedule_script_path': self.dhcp_reschedule_script_path,
            'dhcp_agent_scheduler_dir': self.dhcp_agent_scheduler_dir,
            'log': self.log,
            'hostname': self.hostname,
            'fqdn': self.fqdn,
            'uname': self.uname,
            'mac': self.mac,
            'role': self.role,
            'skip': self.skip,
            'deploy_mode': self.deploy_mode,
            'os': self.os,
            'os_version': self.os_version,
            'user': self.user,
            'passwd': self.passwd,
            'uplink_interfaces': self.uplink_interfaces,
            'uplink_mtu': self.uplink_mtu,
            'install_ivs': self.install_ivs,
            'install_bsnstacklib': self.install_bsnstacklib,
            'install_all': self.install_all,
            'deploy_dhcp_agent': self.deploy_dhcp_agent,
            'deploy_l3_agent': self.deploy_l3_agent,
            'bridges': str(self.bridges),
            'br_bond': self.br_bond,
            'bond': self.bond,
            'pxe_interface': self.pxe_interface,
            'br_fw_admin': self.br_fw_admin,
            'br_fw_admin_address': self.br_fw_admin_address,
            'tagged_intfs': self.tagged_intfs,
            'ex_gw': self.ex_gw,
            'tag': self.tag,
            'env_tag': self.env_tag,
            'pip_proxy': self.pip_proxy,
            'certificate_dir': self.certificate_dir,
            'upgrade_dir': self.upgrade_dir,
            'upgrade_pkgs': self.upgrade_pkgs,
            'cleanup': self.cleanup,
            'rabbit_hosts': self.rabbit_hosts,
            'keystone_auth_url': self.keystone_auth_url,
            'keystone_auth_user': self.keystone_auth_user,
            'keystone_password': self.keystone_password,
            'keystone_auth_tenant': self.keystone_auth_tenant,
            'time_diff': self.time_diff,
            'last_log': self.last_log,
            'rhosp_automate_register': self.rhosp_automate_register,
            'rhosp_installer_management_interface':
                self.rhosp_installer_management_interface,
            'rhosp_installer_pxe_interface':
                self.rhosp_installer_pxe_interface,
            'rhosp_undercloud_dns': self.rhosp_undercloud_dns,
            'rhosp_register_username': self.rhosp_register_username,
            'rhosp_register_passwd': self.rhosp_register_passwd,
            'installer_pxe_interface_ip': self.installer_pxe_interface_ip,
            'neutron_id': self.neutron_id,
            'tenant_api_version': self.tenant_api_version,
            'openstack_release': self.openstack_release,
            'bsnstacklib_version_lower': self.get_bsnstacklib_version_lower(),
            'bsnstacklib_version_upper': self.get_bsnstacklib_version_upper(),
            'bcf_version': self.bcf_version,
            'bcf_controllers': self.bcf_controllers,
            'bcf_controller_ips': self.bcf_controller_ips,
            'bcf_controller_user': self.bcf_controller_user,
            'bcf_controller_passwd': self.bcf_controller_passwd,
            'bcf_openstack_management_tenant':
                self.bcf_openstack_management_tenant,
            'bcf_master': self.bcf_master,
            'physnet': self.physnet,
            'lower_vlan': self.lower_vlan,
            'upper_vlan': self.upper_vlan,
            'setup_node_ip': self.setup_node_ip,
            'setup_node_dir': self.setup_node_dir,
            'selinux_mode': self.selinux_mode,
            'fuel_cluster_id': self.fuel_cluster_id,
            'rhosp': self.rhosp,
            'ivs_pkg': self.ivs_pkg,
            'ivs_debug_pkg': self.ivs_debug_pkg,
            'ivs_version': self.ivs_version,
            'old_ivs_version': self.old_ivs_version,
            'error': self.error})

    def __repr__(self):
        return self.__str__()
