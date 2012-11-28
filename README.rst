Swallow (XMP-16) ethernet loader
.......

:Version:  0.0.1

:Status:  Alpha

:Maintainer:  https://github.com/stevekerrison

:Description:  Implements an Ethernet peripheral to allow network booting of a Swallow compute grid.


Key Features
============

* Uses module_swallow_xlinkboot to initialise a network of Swallow boards
* Uses the XMOS ethernet stack to provide a mechanism for network booting cores
* Can also provide ethernet based data I/O

To Do
=====

* Lots, see commit logs and comments

Known Issues
============

* TCP not supported

Required Repositories
================

* sc_swallow_communication (https://github.com/stevekerrison/sc_swallow_communication)
* sw_swallow_xlinkboot (https://github.com/stevekerrison/sc_swallow_xlinkboot)
* sc_ethernet (https://github.com/xcore/sc_ethernet)
* sc_xtcp (https://github.com/xcore/sc_xtcp)

Support
=======

Fork, fix and pull-request! Feel free to contact maintainer with any questions.

Using this software
===================

See the source for more enlightenment on what is explained below:

A MAC address and IP can be configured. The default MAC uses XMOS's VID and the IP is an appropriate private IP.

The software will not solicit ARPs, but only receive/respond. The first valid request it receives will be designated as
the destination IP. Although it may respond to further ARPs, IP communication to anything but the IP that first ARP'd
the device will fail. This suits our operation model of a single machine controlling this device or a group of these
devices (i.e. a perimeter of ethernet devices surrounding a Swallow compute grid).

ICMP echo (ping) is supported, but only if an ARP has been seen in order to prepare the response header.

UDP is used for simplistic data transfer, so care should be taken if reliable delivery is required that the network
and software doesn't work. Port 69 is used for booting cores (TFTP server - TODO). Port 9191 (0x5b5b) is used for data
streaming. Checksums are not used and so the UDP checksum field should be 0.

Data transfer
-------------

Data inbound should be sent to UDP port 9191. Its source address and port should be the desired IP and port for outbound
data.

The UDP payload format is as follows:

+============================================================================================================+
|  16-bits   |    8-bits  | 8-bits |  16-bits   |    8-bits  | 8-bits   | 8-bits | 24-bits | n-bits | 16-bits|
+------------|------------|--------|------------|------------|----------|--------|---------|--------|--------+
| Dest. Node | Dest. Chan |  0x02  | Rtn. Node  |  Rtn. Chan | Rtn Flag | Format | Length  |  Data  | Tail   |
+============================================================================================================+

Dest. Node: The logical node ID of the destination core. This will be translated into the actual node ID, so nodes
 can be addressed contiguously externally, whilst they might not be so internally.
Dest. Chan: The chanend to communicate to followed by 0x02 to represent a channel resource
Rtn. Node: The logical node ID to which the destination to should respond.
Rtn. Chan: The chanend to which the destination should respond.
Rtn Flag: If 0x01 then Rtn. Node and Rt. Chan are transmitted. If 0x00 then the Ethernet board's receiver channel is
 used instead. If 0x02 then the ethernet's sender channel end is used and a handshake is performed at the beginning.
 All other values are invalid.
Format: 0x1 means single-token INT/OUTT instructions are used, 0x4 means 4-byte IN/OUT instructions are used.
Length: Format * Length = Number of bytes in Data section
Data: The payload to send.
Tail: The control token(s) to send. Second byte may be 0 if it is not needed.
 If Rtn Flag was 0x02 then if a CT_END is sent, the remote channel end will reply to the
 Ethernet's local channel end with a CT_END as well. If 0x40 is sent as the first control token, this indicates to the
 remote end that more data will be coming later, but that the route will be re-established.

The behaviour of the receiving chanend will depend on the application and the data being delivered.

The length field allows the datagram to be fragmented. If the packet ends before length reached, the next packet to port
9191 is assumed to be a continuation, only containing the rest of the data field and the tail byte. This is obviously
potentially problematic if there are multiple connections to 9191. Alternatively one might opt to split a large block
of data across multiple packets manually and set the tail of each packet to 0x0 to avoid closing the route down on the
grid. This presents the same issue, because if the next packet to 9191 is not a continuation then deadlock will probably
occur. By sending an 0x40 control token and an END or PAUSE token, fragmentation issues can be avoided. Data outbound
from the grid to the control machine will never have fragmented packets and so will always use 0x40 to indicate if
more data is coming.



