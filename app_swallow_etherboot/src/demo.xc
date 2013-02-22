// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*
 * Demo of swallow ethernet, based on sc_ethernet demo code
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 */

/*************************************************************************
 *
 * Ethernet MAC Layer Client Test Code
 * IEEE 802.3 MAC Client
 *
 *
 *************************************************************************
 *
 * ARP/ICMP demo
 * Note: Only supports unfragmented IP packets
 *
 *************************************************************************/

#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include <platform.h>
#include <stdlib.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "checksum.h"
#include "xscope.h"
#include "swallow_ethernet.h"
#include "swallow_comms.h"

// If you have a board with the xscope xlink enabled (e.g. the XC-2) then
// change this define to 0, make sure you also remove the -lxscope from
// the build flags in the Makefile
//#define USE_XSCOPE 1

#define ETHERNET_DEFAULT_TILE stdcore[0]

/* XLinkboot stuff */
#include "swallow_xlinkboot.h"
//out port swallow_rst = XS1_PORT_1D; //I on old, D on new
//struct xlinkboot_pll_t PLLs[1] = {{-1,0,-1,0x00002700,1,5}};
struct swallow_xlinkboot_cfg swxlb_cfg = {
  2,
  3,
  1,
  SWXLB_POS_BOTTOM,
  {{-1,0,-1,0x00002700,1,5}},
  1,
  XS1_PORT_1D //I on old, D on new
};

#if USE_XSCOPE
void xscope_user_init(void) {
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
}
#endif

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

void grid_example(streaming chanend x)
{
  unsigned dst, format, length, w;
  while(1)
  {
    startTransactionServer(x,dst,format,length);
    //We assume we are format = 0x4, because we're lazy in this demo
    for (int i = 0; i < length; i += 1)
    {
      streamInWord(x,w);
      printhexln(byterev(w));
    }
    endTransactionServer(x);
  }
}

int main()
{
  chan rx[1], tx[1], tx_into_swallow;
  streaming chan rx_from_swallow;
  chan x;
  par
    {
      //::ethernet
      on ETHERNET_DEFAULT_TILE:
      {
        char mac_address[6] = {0x00,0x22,0x97,0x5b,0x00,0x01};
        //otp_board_info_get_mac(otp_ports, 0, mac_dummy);
        //swallow_xlinkboot(2,3,1,SWXLB_POS_BOTTOM,PLLs,1,swallow_rst);
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
          swallow_ethernet(tx[0], rx[0], tx_into_swallow, rx_from_swallow,swxlb_cfg);
          /*{
            timer t;
            unsigned tv;
            t :> tv;
            t when timerafter(tv + 0x10000000) :> void;
            startTransactionClient(x,0xB0D0402,0,0);
            endTransactionClient(x);
          }*/
        }
      }
      //::
    }

	return 0;
}
