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

#define MAX(x,y) ((x < y) ? y : x)
#define DEBUG_PC_PAYLOAD_LIMIT 1400

struct swallow_debug_pc {
  unsigned short logical_id, node_id, jtag_id, reserved;
  unsigned int thread_pc[8];
};

void swallow_ethernet(chanend rx, chanend tx, streaming chanend grid_tx, streaming chanend grid_rx,
  streaming chanend grid_print, struct swallow_xlinkboot_cfg &cfg);

void udp_copy_header(unsigned char rxbuf[], unsigned char txbuf[],
  unsigned udp_len);
unsigned udp_prep_header(unsigned char txbuf[], unsigned payload_len);
