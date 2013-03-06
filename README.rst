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

Data inbound should be sent to UDP port 23387. Its source address and port should be the desired IP and port for outbound
data.

The UDP payload format is as follows:

+========================================================================+
| 16-bits |  16-bits   |    8-bits  | 8-bits | 8-bits | 24-bits | n-bits |
+---------|------------|------------|--------|--------|---------|--------+
| 0xda7a  | Dest. Node | Dest. Chan |  0x02  | Format | Length  |  Data  |
+========================================================================+

0xda7a (data) : A header to identify this packet and improve alignment of the data once it's in the grid.
Dest. Node: The logical node ID of the destination core. This will be translated into the actual node ID, so nodes
 can be addressed contiguously externally, whilst they might not be so internally.
Dest. Chan: The chanend to communicate to followed by 0x02 to represent a channel resource
Format: 0x1 means single-token INT/OUTT instructions are used, 0x4 means 4-byte IN/OUT instructions are used.
Length: Format * Length = Number of bytes in Data section
Data: The payload to send.

The behaviour of the receiving chanend will depend on the application and the data being delivered.

The data field should never be more than MTU-44 bytes in size. Fragmented packets are not supported.
If the length field is greater than MTU-44 bytes, then behaviour is undefined.

TFTP
----

A TFTP server allows you to load code onto the grid. Simply connect to port 69 with a TFTP application in octet or
binary mode (NOT binascii).

Performing `get $filename` will fetch an ASCII file containing "boards_h,boards_w", regardless of the file requested.

Performing `put $filename` and the device will attempt to load the supplied file, provided it is in SGB (Swallow Grid
Binary) format. Please see the swallow_mcsc repository for a definition of the SGB format.


