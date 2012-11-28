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
  ETH_TX_CLK,
  ETH_TX_EN,
  ETH_TXD,
};

struct mii_rx mrx = {
  XS1_CLKBLK_1,
  ETH_RX_CLK,
  ETH_RXD,
  ETH_RX_DV,
};

int main(void)
{
  chan txapp, rxapp;
  struct ipconfig cfg = { {0x0022975b,0x00010000}, {192,168,128,3}, {255,255,255,0}};
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
  printstrln("Let the games begin...");
  par
  {
    swallow_ethernet(cfg,mtx,mrx,txapp,rxapp);
    /*{while(1);};
    {while(1);};
    {while(1);};
    {while(1);};*/
  }
  return 0;
}
