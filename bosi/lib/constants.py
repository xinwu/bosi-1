# uname -n cutoff length for port group name
UNAME_CUTOFF = 249

# max number of threads, each thread sets up one node
MAX_WORKERS = 10

# root access to all the nodes is required
DEFAULT_USER = 'root'

# key words to specify node role in yaml config
ROLE_NEUTRON_SERVER = 'controller'
ROLE_COMPUTE = 'compute'
ROLE_CEPH = 'ceph-osd'
ROLE_CINDER = "cinder"
ROLE_MONGO = 'mongo'

# deployment t6/t5
T6 = 't6'
T5 = 't5'

MODE_DICT = {'pfabric': T5,
             'pvfabric': T6}

OS_RELEASE_JUNO = 'juno'
OS_RELEASE_KILO = 'kilo'
OS_RELEASE_KILO_V2 = 'kilo_v2'
OS_RELEASE_LIBERTY = 'liberty'

# openstack release to bsnstacklib version
OS_RELEASE_TO_BSN_LIB_LOWER = {OS_RELEASE_JUNO: '2014.2',
                               OS_RELEASE_KILO_V2: '2015.1',
                               OS_RELEASE_KILO: '2015.2',
                               OS_RELEASE_LIBERTY: '2015.3'}
OS_RELEASE_TO_BSN_LIB_UPPER = {OS_RELEASE_JUNO: '2015.1',
                               OS_RELEASE_KILO_V2: '2015.2',
                               OS_RELEASE_KILO: '2015.3',
                               OS_RELEASE_LIBERTY: '2015.4'}

# Since kilo and BCF 3.5, we use tenant name
# instead of tenant uuid to configure tenants,
# The default version is 2. However, in case
# of upgrade, where tenant configuraion was
# using uuid, user needs to use version 1
# to make upgrade happen.
TENANT_UUID_API_VERSION = 1
TENANT_NAME_API_VERSION = 2

IVS_TAR_PKG_DIRS = ["pkg/centos7-x86_64", "pkg/trusty-amd64"]

# horizon patch
DEPLOY_HORIZON_PATCH = False
HORIZON_PATCH_URL = {
    OS_RELEASE_JUNO:    'https://github.com/bigswitch/horizon/archive/'
                        'juno-bcf-3.0-beta1.tar.gz',
    OS_RELEASE_KILO:    'https://github.com/bigswitch/horizon/archive/'
                        'stable/kilo2.tar.gz',
    OS_RELEASE_LIBERTY: 'https://github.com/bigswitch/horizon/archive/'
                        'stable/liberty.tar.gz',
}
HORIZON_PATCH_DIR = {
    OS_RELEASE_JUNO:    'horizon-juno-bcf-3.0-beta1',
    OS_RELEASE_KILO:    'horizon-stable-kilo2',
    OS_RELEASE_LIBERTY: 'horizon-stable-liberty',
}
HORIZON_BASE_DIR = '/usr/share/openstack-dashboard'

# constant file, directory names for each node
PRE_REQUEST_BASH = 'pre_request.sh'
DST_DIR = '/tmp'
GENERATED_SCRIPT_DIR = 'generated_script'
BASH_TEMPLATE_DIR = 'bash_template'
PYTHON_TEMPLATE_DIR = 'python_template'
PUPPET_TEMPLATE_DIR = 'puppet_template'
SELINUX_TEMPLATE_DIR = 'selinux_template'
OSPURGE_TEMPLATE_DIR = 'ospurge_template'
LOG_FILE = "/var/log/bcf_setup.log"

# constants for ivs config
INBAND_VLAN = 4092
IVS_DAEMON_ARGS = (r'''DAEMON_ARGS=\"--hitless --certificate /etc/ivs '''
                   '''--inband-vlan %(inband_vlan)d'''
                   '''%(uplink_interfaces)s%(internal_ports)s\\"''')

# constants of supported OSes and versions
CENTOS = 'centos'
CENTOS_VERSIONS = ['7']
UBUNTU = 'ubuntu'
UBUNTU_VERSIONS = ['14']
REDHAT = 'redhat'
REDHAT_VERSIONS = ['7']

# OSes that uses rpm or deb packages
RPM_OS_SET = [CENTOS, REDHAT]
DEB_OS_SET = [UBUNTU]

# regular expressions
EXISTING_NETWORK_VLAN_RANGE_EXPRESSION = (
    '^\s*network_vlan_ranges\s*=\s*(\S*)\s*:\s*(\S*)\s*:\s*(\S*)\s*$')
NETWORK_VLAN_RANGE_EXPRESSION = '^\s*(\S*)\s*:\s*(\S*)\s*:\s*(\S*)\s*$'
VLAN_RANGE_CONFIG_PATH = '/etc/neutron/plugins/ml2/ml2_conf.ini'
SELINUX_MODE_EXPRESSION = '^\s*SELINUX\s*=\s*(\S*)\s*$'
SELINUX_CONFIG_PATH = '/etc/selinux/config'


# openrc
FUEL_OPENRC = '/root/openrc'
PACKSTACK_OPENRC = '/root/keystonerc_admin'
MANUAL_OPENRC = '/root/admin-openrc.sh'
RHOSP_UNDERCLOUD_OPENRC = '/home/stack/stackrc'
RHOSP_OVERCLOUD_OPENRC = '/home/stack/overcloudrc'

# fuel constants
NONE_IP = 'none'
BR_KEY_PRIVATE = 'neutron/private'
BR_KEY_FW_ADMIN = 'fw-admin'
BR_NAME_INT = 'br-int'

# ivs internal port prefix mapping
IVS_INTERNAL_PORT_DIC = {
    'management': 'm',
    'ex': 'e',
    'storage': 's'}

HASH_HEADER = 'BCF-SETUP'
BCF_CONTROLLER_PORT = 8443
ANY = 'any'

# T5 for Centos requires extra params when using packstack
T5_CENTOS_BOND_BRIDGE = 'br-bond0'
T5_CENTOS_BOND_NAME = 'bond0'

# big db error message
ELEMENT_EXISTS = "List element already exists"

# directory for csr
CSR_DIR = "/tmp/csr"
KEY_DIR = "/tmp/key"

# constants for csr
CSR_SUB = r'''/C=US/ST=California/L=Santa Clara/O=BSN/CN=%(cn)s'''

# support constants
SUPPORT_DIR = "/tmp/support"
