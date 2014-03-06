#!/usr/bin/python

import socket,time,struct

IP_MTU_DISCOVER   = 10
IP_PMTUDISC_DONT  =  0  # Never send DF frames.
IP_PMTUDISC_WANT  =  1  # Use per route hints.
IP_PMTUDISC_DO    =  2  # Always DF.
IP_PMTUDISC_PROBE =  3  # Ignore dst pmtu.

swallow_ip            = "192.168.128.3"
swallow_debug_port    = 0x5bdb
swallow_loopback_port = 0x1b1b
swallow_comms_port    = 0x5b5b

sock = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_IP, IP_MTU_DISCOVER, IP_PMTUDISC_DONT)

pkt = ''
dest = (swallow_ip,swallow_debug_port)

debug_struct_size = 40

while True:
  time.sleep(0.5)
  sock.sendto(pkt,dest)
  data,addr = sock.recvfrom(2048)
  cores = len(data)/debug_struct_size
  for i in xrange(cores):
    lid = struct.unpack('!H',data[i * debug_struct_size:][:2])[0]
    nid = struct.unpack('!H',data[i * debug_struct_size + 2:][:2])[0]
    jid = struct.unpack('!H',data[i * debug_struct_size + 4:][:2])[0]
    print """Locical: {:05d} | Node: 0x{:04x} | JTAG: 0x{:04x}
  T : PC""".format(
      lid,nid,jid)
    for t in xrange(8):
      pc = struct.unpack('!I',data[i * debug_struct_size + 8 + t * 4:][:4])[0]
      print "  {} : 0x{:08x}".format(t,pc)
  break
