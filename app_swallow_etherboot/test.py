#!/usr/bin/python

import socket,time

sock = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
dest = ("192.168.128.3",0x1b1b)
pkt = "a" * 1472

"""for i in range(1):
	sock.sendto(pkt,dest)"""
for i in range(120):
	sock.sendto(pkt,dest)
time.sleep(0.1)
for i in range(100000):
	sock.sendto(pkt,dest)
	time.sleep(0.0001025)
