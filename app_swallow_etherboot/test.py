#!/usr/bin/python

import socket,time

IP_MTU_DISCOVER   = 10
IP_PMTUDISC_DONT  =  0  # Never send DF frames.
IP_PMTUDISC_WANT  =  1  # Use per route hints.
IP_PMTUDISC_DO    =  2  # Always DF.
IP_PMTUDISC_PROBE =  3  # Ignore dst pmtu.

sock = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_IP, IP_MTU_DISCOVER, IP_PMTUDISC_DONT)
dest = ("192.168.128.3",0x1b1b)
pkt = 'a' * 1472

"""for i in range(1):
	sock.sendto(pkt,dest)"""


pkt = ''.join(map(chr,[0xda,0x7a,0x00,0x00,0x03,0x02,0x04,0x00,0x00,0x00,0xde, \
	0xad,0xbe,0xef,0xba,0xbe,0xca,0xfe,0xf0,0x0d,0xfe,0xed]))
dest = ("192.168.128.3",0x5b5b)
sock.sendto(pkt,dest)

"""for i in range(120):
	sock.sendto(pkt,dest)
time.sleep(0.1)
for i in range(100000):
	sock.sendto(pkt,dest)
	time.sleep(0.0001025)"""
