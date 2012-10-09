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


Required Repositories
================

sc_swallow_communication (https://github.com/stevekerrison/sc_swallow_communication)
sw_swallow_xlinkboot (https://github.com/stevekerrison/sc_swallow_xlinkboot)
sc_ethernet (https://github.com/xcore/sc_ethernet)
sc_xtcp (https://github.com/xcore/sc_xtcp)

Support
=======

Fork, fix and pull-request! Feel free to contact maintainer with any questions.
