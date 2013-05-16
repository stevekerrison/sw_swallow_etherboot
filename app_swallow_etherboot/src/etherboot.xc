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
#include "otp_board_info.h"
#include "ethernet.h"
#include "checksum.h"
//#include "xscope.h"
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


int main()
{
  chan rx[1], tx[1];
  streaming chan rx_from_swallow, tx_into_swallow, swallow_print;
  chan x;
  par
    {
      //::ethernet
      on ETHERNET_DEFAULT_TILE:
      {
        char mac_address[6] = SWALLOW_MAC;
        eth_phy_reset(eth_rst);
        smi_init(smi);
        eth_phy_config(1, smi);
        ethernet_server(mii,
                        null,
                        mac_address,
                        rx, 1,
                        tx, 1);
      }
      on ETHERNET_DEFAULT_TILE : {
        par {
          swallow_ethernet(tx[0], rx[0], tx_into_swallow, rx_from_swallow, swallow_print, swxlb_cfg);
          //outbound_example(rx_from_swallow);
          /*{
            timer t;
            unsigned tv;
            t :> tv;
            t when timerafter(tv + 0x10000000) :> void;
            startTransactionClient(x,0x80010402,0,0);
            endTransactionClient(x);
          }*/
        }
      }
      //::
    }

	return 0;
}
