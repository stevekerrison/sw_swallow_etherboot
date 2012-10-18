/*
 * swallow_etherboot - Boot a Swallow grid using Ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

#include <platform.h>
#include <swallow_ethernet.h>
#include <xscope.h>
#include <print.h>

struct mii_tx mtx = {
  XS1_CLKBLK_2,
  PORT_ETH_TXCLK,
  PORT_ETH_TXEN,
  PORT_ETH_TXD,
};

struct mii_rx mrx = {
  XS1_CLKBLK_1,
  PORT_ETH_RXCLK,
  XS1_PORT_1H,
  PORT_ETH_RXD,
  PORT_ETH_RXDV,
};

int main(void)
{
  chan txapp, rxapp;
  struct ipconfig cfg = { {0x0022975b,0x00010000}, {3,128,168,192}};
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
  printstrln("Let the games begin...");
  swallow_ethernet(cfg,mtx,mrx,txapp,rxapp);
  return 0;
}
