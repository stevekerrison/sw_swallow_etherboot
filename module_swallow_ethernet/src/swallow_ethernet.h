/*
 * swallow_ethernet - "Application layer" thread
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#include "swallow_xlinkboot.h"
 
//::ip_address_define
// NOTE: YOU MAY NEED TO REDEFINE THIS TO AN IP ADDRESS THAT WORKS
// FOR YOUR NETWORK
#define OWN_IP_ADDRESS {192, 168, 128, 3}
//::

void swallow_ethernet(chanend rx, chanend tx, streaming chanend grid_tx, streaming chanend grid_rx,
  streaming chanend grid_print, struct swallow_xlinkboot_cfg &cfg);
