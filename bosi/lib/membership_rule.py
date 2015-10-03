import constants as const


class MembershipRule(object):
    def __init__(self, br_key, br_vlan, tenant, cluster_id):
        prefixes = br_key.split('/')
        segment = prefixes[len(prefixes) - 1]
        self.segment = segment
        self.br_vlan = br_vlan
        self.tenant = tenant
        self.cluster_id = cluster_id
        internal_port_prefix = const.IVS_INTERNAL_PORT_DIC.get(segment)
        self.internal_port = "%s%s" % (internal_port_prefix, cluster_id)

    def __str__(self):
        return (r'''{segment: %(segment)s, br_vlan: %(br_vlan)s, '''
                '''cluster_id: %(cluster_id)s, internal_port: '''
                '''%(internal_port)s}''' %
               {'segment': self.segment, 'br_vlan': self.br_vlan,
                'tenant': self.tenant, 'cluster_id': self.cluster_id,
                'internal_port': self.internal_port})

    def __repr__(self):
        return self.__str__()
