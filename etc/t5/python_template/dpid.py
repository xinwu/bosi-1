#!/usr/bin/python
# Print the MAC address of the first non-loopback NIC.
# Based on http://programmaticallyspeaking.com/getting-network-interfaces-in-python.html.
# Based on getifaddrs.py from pydlnadms [http://code.google.com/p/pydlnadms/].

from socket import AF_INET, AF_INET6, AF_PACKET, inet_ntop
from ctypes import (
    Structure, Union, POINTER,
    pointer, get_errno, cast,
    c_ushort, c_byte, c_void_p, c_char_p, c_uint, c_int, c_uint16, c_uint32
)
import ctypes.util
import ctypes

IFF_LOOPBACK = 8

class struct_sockaddr(Structure):
    _fields_ = [
        ('sa_family', c_ushort),
        ('sa_data', c_byte * 14),]

class struct_sockaddr_ll(Structure):
    _fields_ = [
        ('sll_family', c_ushort),
        ('sll_protocol', c_uint16),
        ('sll_ifindex', c_int),
        ('sll_hatype', c_ushort),
        ('sll_pkttype', c_byte),
        ('sll_halen', c_byte),
        ('sll_addr', c_byte * 8)]

class union_ifa_ifu(Union):
    _fields_ = [
        ('ifu_broadaddr', POINTER(struct_sockaddr)),
        ('ifu_dstaddr', POINTER(struct_sockaddr)),]

class struct_ifaddrs(Structure):
    pass
struct_ifaddrs._fields_ = [
    ('ifa_next', POINTER(struct_ifaddrs)),
    ('ifa_name', c_char_p),
    ('ifa_flags', c_uint),
    ('ifa_addr', POINTER(struct_sockaddr)),
    ('ifa_netmask', POINTER(struct_sockaddr)),
    ('ifa_ifu', union_ifa_ifu),
    ('ifa_data', c_void_p),]

libc = ctypes.CDLL(ctypes.util.find_library('c'))

def ifap_iter(ifap):
    ifa = ifap.contents
    while True:
        yield ifa
        if not ifa.ifa_next:
            break
        ifa = ifa.ifa_next.contents

def get_mac():
    ifap = POINTER(struct_ifaddrs)()
    result = libc.getifaddrs(pointer(ifap))
    if result != 0:
        raise OSError(get_errno())
    del result
    try:
        for ifa in ifap_iter(ifap):
            if ifa.ifa_flags & IFF_LOOPBACK:
                continue
            sa = cast(ifa.ifa_addr, POINTER(struct_sockaddr_ll)).contents
            if sa.sll_family != AF_PACKET:
                continue
            mac = ':'.join("%02x" % (x & 0xff) for x in sa.sll_addr[:sa.sll_halen])
            return mac
    finally:
        libc.freeifaddrs(ifap)

if __name__ == '__main__':
    print get_mac()

