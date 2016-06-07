import constants as const
import httplib
import json
from util import safe_print


class RestLib(object):
    @staticmethod
    def request(url, prefix="/api/v1/data/controller/", method='GET',
                data='', hashPath=None, host="127.0.0.1:8443", cookie=None):
        headers = {'Content-type': 'application/json'}

        if cookie:
            headers['Cookie'] = 'session_cookie=%s' % cookie

        if hashPath:
            headers[const.HASH_HEADER] = hashPath

        connection = httplib.HTTPSConnection(host)

        try:
            connection.request(method, prefix + url, data, headers)
            response = connection.getresponse()
            ret = (response.status, response.reason, response.read(),
                   response.getheader(const.HASH_HEADER))
            with open(const.LOG_FILE, "a") as log_file:
                log_file.write('Controller REQUEST: %s %s:body=%r\n' %
                              (method, host + prefix + url, data))
                log_file.write('Controller RESPONSE: status=%d reason=%r,'
                               'data=%r, hash=%r\n' % ret)
            return ret
        except Exception as e:
            raise Exception("Controller REQUEST exception: %s" % e)

    @staticmethod
    def get(cookie, url, server, port, hashPath=None):
        host = "%s:%d" % (server, port)
        return RestLib.request(url, hashPath=hashPath, host=host,
                               cookie=cookie)

    @staticmethod
    def post(cookie, url, server, port, data, hashPath=None):
        host = "%s:%d" % (server, port)
        return RestLib.request(url, method='POST', hashPath=hashPath,
                               host=host, data=data, cookie=cookie)

    @staticmethod
    def patch(cookie, url, server, port, data, hashPath=None):
        host = "%s:%d" % (server, port)
        return RestLib.request(url, method='PATCH', hashPath=hashPath,
                               host=host, data=data, cookie=cookie)

    @staticmethod
    def put(cookie, url, server, port, data, hashPath=None):
        host = "%s:%d" % (server, port)
        return RestLib.request(url, method='PUT', hashPath=hashPath,
                               host=host, data=data, cookie=cookie)

    @staticmethod
    def delete(cookie, url, server, port, hashPath=None):
        host = "%s:%d" % (server, port)
        return RestLib.request(url, method='DELETE', hashPath=hashPath,
                               host=host, cookie=cookie)

    @staticmethod
    def auth_bcf(server, username, password, port=const.BCF_CONTROLLER_PORT):
        login = {"user": username, "password": password}
        host = "%s:%d" % (server, port)
        ret = RestLib.request("/api/v1/auth/login", prefix='',
                              method='POST', data=json.dumps(login),
                              host=host)
        session = json.loads(ret[2])
        if ret[0] != 200:
            raise Exception(ret)
        if ("session_cookie" not in session):
            raise Exception("Failed to authenticate: session cookie not set")
        return session["session_cookie"]

    @staticmethod
    def logout_bcf(cookie, server, port=const.BCF_CONTROLLER_PORT):
        url = "core/aaa/session[auth-token=\"%s\"]" % cookie
        ret = RestLib.delete(cookie, url, server, port)
        return ret

    @staticmethod
    def use_port_group(server, cookie,
                       port=const.BCF_CONTROLLER_PORT):
        url = (r'''core/version/appliance''')
        res = RestLib.get(cookie, url, server, port)[2]
        if '3.5' in res:
            return True
        return False

    @staticmethod
    def get_active_bcf_controller(servers, username, password,
                                  port=const.BCF_CONTROLLER_PORT):
        for server in servers:
            try:
                cookie = RestLib.auth_bcf(server, username, password, port)
                url = 'core/controller/role'
                res = RestLib.get(cookie, url, server, port)[2]
                if 'active' in res:
                    return server, cookie
            except Exception:
                continue
        return None, None

    @staticmethod
    def get_os_mgmt_segments(server, cookie, tenant,
                             port=const.BCF_CONTROLLER_PORT):
        url = (r'''applications/bcf/info/endpoint-manager/segment'''
               '''[tenant="%(tenant)s"]''' %
               {'tenant': tenant})
        ret = RestLib.get(cookie, url, server, port)
        if ret[0] != 200:
            raise Exception(ret)
        res = json.loads(ret[2])
        segments = []
        for segment in res:
            # 'management' or 'Management' segment does not matter
            segments.append(segment['name'].lower())
        return segments

    @staticmethod
    def program_segment_and_membership_rule(server, cookie, rule, tenant,
                                            port=const.BCF_CONTROLLER_PORT):

        use_port_group = RestLib.use_port_group(server, cookie)
        pg_key='interface'
        if use_port_group:
            pg_key='port'
        
        if rule.segment not in const.IVS_INTERNAL_PORT_DIC:
            return

        existing_segments = RestLib.get_os_mgmt_segments(
            server, cookie, tenant, port)
        if rule.segment not in existing_segments:
            with open(const.LOG_FILE, "a") as log_file:
                msg = (r'''Warning: BCF controller does not have tenant '''
                       '''%(tenant)s segment %(segment)s\n''' %
                       {'tenant': tenant, 'segment': rule.segment})
                safe_print(msg)
                log_file.write(msg)
            return

        segment_url = (r'''applications/bcf/tenant[name="%(tenant)s"]/segment''' %
                       {'tenant': tenant})
        segment_data = {"name": rule.segment}
        safe_print("Configuring BCF Segment: Tenant %s, Segment %s\n" %
                   (tenant, rule.segment))
        try:
            ret = RestLib.post(cookie, segment_url, server, port,
                               json.dumps(segment_data))
        except Exception:
            ret = RestLib.patch(cookie, segment_url, server, port,
                                json.dumps(segment_data))
        if ret[0] != 204:
            if (ret[0] != 409 or
                const.ELEMENT_EXISTS not in ret[2]):
                raise Exception(ret)

        if rule.br_vlan:
            vlan = int(rule.br_vlan)
        else:
            vlan = -1

        intf_rule_url = (r'''applications/bcf/tenant[name="%(tenant)s"]/'''
                         '''segment[name="%(segment)s"]/'''
                         '''switch-port-membership-rule''' %
                         {'tenant': tenant,
                          'segment': rule.segment})
        rule_data = {"interface": const.ANY, "switch": const.ANY, "vlan": vlan}
        safe_print("Configuring BCF Segment rule: Tenant %s, Segment "
                   "%s Rule: member switch any interface any vlan %d\n"
                   % (tenant, rule.segment, vlan))
        try:
            ret = RestLib.post(cookie, intf_rule_url, server, port,
                               json.dumps(rule_data))
        except Exception:
            ret = RestLib.patch(cookie, intf_rule_url, server, port,
                                json.dumps(rule_data))
        if ret[0] != 204:
            if (ret[0] != 409 or
                const.ELEMENT_EXISTS not in ret[2]):
                raise Exception(ret)

        pg_rule_url = (r'''applications/bcf/tenant[name="%(tenant)s"]/'''
                       '''segment[name="%(segment)s"]/'''
                       '''%(pg_key)s-group-membership-rule''' %
                       {'tenant': tenant,
                        'pg_key': pg_key,
                        'segment': rule.segment})
        rule_data = {"%s-group" % pg_key: const.ANY, "vlan": vlan}
        safe_print("Configuring BCF Segment rule: Tenant %s, "
                   "Segment %s Rule: member %s-group any vlan %d\n"
                   % (tenant, rule.segment, pg_key, vlan))
        try:
            ret = RestLib.post(cookie, pg_rule_url, server, port,
                               json.dumps(rule_data))
        except Exception:
            ret = RestLib.patch(cookie, pg_rule_url, server, port,
                                json.dumps(rule_data))
        if ret[0] != 204:
            if (ret[0] != 409 or
                const.ELEMENT_EXISTS not in ret[2]):
                raise Exception(ret)

        specific_rule_url = (r'''applications/bcf/tenant[name="%(tenant)s"]/'''
                             '''segment[name="%(segment)s"]/'''
                             '''switch-port-membership-rule''' %
                             {'tenant': tenant,
                              'segment': rule.segment})
        rule_data = {"interface": rule.internal_port,
                     "switch": const.ANY, "vlan": -1}
        safe_print("Configuring BCF Segment rule: Tenant %s, Segment %s Rule: "
                   "member switch any interface %s vlan untagged\n"
                   % (tenant, rule.segment, rule.internal_port))
        try:
            ret = RestLib.post(cookie, specific_rule_url, server, port,
                               json.dumps(rule_data))
        except Exception:
            ret = RestLib.patch(cookie, specific_rule_url, server, port,
                                json.dumps(rule_data))
        if ret[0] != 204:
            if (ret[0] != 409 or
                const.ELEMENT_EXISTS not in ret[2]):
                raise Exception(ret)
