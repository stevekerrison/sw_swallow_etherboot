// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*
 * Swallow ethernet, providing TFTP services
 *
 * Copyright (C) 2012-2013 Steve Kerrison <github@stevekerrison.com>
 *
 */

#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include <platform.h>
#include <stdlib.h>
#include <xscope.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "checksum.h"
#include "swallow_ethernet.h"
#include "swallow_comms.h"

// If you have a board with the xscope xlink enabled (e.g. the XC-2) then
// change this define to 0, make sure you also remove the -lxscope from
// the build flags in the Makefile
//#define USE_XSCOPE 1

#define ETHERNET_DEFAULT_TILE stdcore[0]

/* XLinkboot stuff */
#include "swallow_xlinkboot.h"

/* Config is now in a separate file to keep things tidy */
#include "swallow_etherboot_conf.h"



// Port Definitions

// These ports are for accessing the OTP memory
on ETHERNET_DEFAULT_TILE: otp_ports_t otp_ports = OTP_PORTS_INITIALIZER;
on ETHERNET_DEFAULT_TILE: out port led = L1_LED;

// Here are the port definitions required by ethernet
// The intializers are taken from the ethernet_board_support.h header for
// XMOS dev boards. If you are using a different board you will need to
// supply explicit port structure intializers for these values
smi_interface_t smi = { 0, ETH_MDIO, ETH_MDC };
mii_interface_t mii = 
{
  XS1_CLKBLK_1,
  XS1_CLKBLK_2,

  ETH_RX_CLK,
  ETH_RX_ERR,
  ETH_RXD,
  ETH_RX_DV,

  ETH_TX_CLK,
  ETH_TX_EN,
  ETH_TXD,
  ETH_TIMING,
};
ethernet_reset_interface_t eth_rst = ETHERNET_DEFAULT_RESET_INTERFACE_INIT;

void outbound_example(streaming chanend x)
{
  timer t;
  /* Normally you'd establish what the remote ID of X would be,
  * but seeing as we have connected it 1-1 we don't have
  * to worry */
  unsigned tv, dst = getRemoteStreamingChanendId(x);
  while (1)
  {
    t :> tv;
    t when timerafter(tv + 0x20000000) :> void;
    startTransactionClient(x,dst,4,16);
    for (int i = 0; i < 16; i += 1)
    {
      x <: 0xbabecafe;
    }
    endTransactionClient(x);
  }
  
}

void grid_example(streaming chanend x)
{
  unsigned dst, format, length, w;
  while(1)
  {
    startTransactionServer(x,dst,format,length);
    //We assume we are format = 0x4, because we're lazy in this demo
    for (int i = 0; i < length; i += 1)
    {
      x <: w;
      printhexln(byterev(w));
    }
    endTransactionServer(x);
  }
}

#define SLOW_LINK 0x80063d8e
#define MODEBITS_JTAG 0x10012

/* Enables XLink and tries to talk to the grid. Triggers a reset if something
 * goes wrong and we're not attached to JTAG */
void etherboot_init(void) {
  unsigned tid = get_local_tile_id(), data, tv, link, jtag, dir,lastdata;
  timer t;
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
  jtag = getps(0x030b) == MODEBITS_JTAG;
  /* If vertical ID bits are set, we're NOT on top, so are using link D. */
  if ((tid >> SWXLB_VPOS) & COUNT_FROM_BITS(SWXLB_VBITS)) {
    link = XLB_L_LINKD;
  } else {
    link = XLB_L_LINKC;
  }
  data = SLOW_LINK;
  // Bring up the link, wait for the other end to do all the setup for us
  write_sswitch_reg(tid,0x80 + link,data);
  printstrln("Waiting for grid to bring us up...");
  lastdata = data;
  while ((data >> 30) != 3) { //Wait for remote to fully configure us 50wire
    t :> tv;
    t when timerafter(tv + XLB_UP_DELAY) :> void;
    read_sswitch_reg(tid,0x80 + link,data);
    if ((data >> 27) & 1) { //ERROR!
      printstrln("Error on the XLink!");
      if (!jtag) { //Reset!
        read_sswitch_reg(tid,0x06,data);
        write_sswitch_reg(tid,0x06,data);
        //Core reboots here!
      }
    }
  }
  printstrln("Grid brought us up successfully");
  led <: 1;
}

int main()
{
  chan rx[1], tx[1];
  streaming chan rx_from_swallow, tx_into_swallow, swallow_print;
  par
    {
      //::ethernet
      on ETHERNET_DEFAULT_TILE:
      {
        char mac_address[6] = SWALLOW_MAC;
        etherboot_init();
        eth_phy_reset(eth_rst);
        smi_init(smi);
        eth_phy_config(1, smi);
        par {
          ethernet_server(mii, null, mac_address, rx, 1, tx, 1);
          swallow_ethernet(tx[0], rx[0], tx_into_swallow, rx_from_swallow,
            swallow_print, swxlb_cfg);
        }
      }
    }

	return 0;
}
