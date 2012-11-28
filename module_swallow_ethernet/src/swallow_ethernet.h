/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef SWALLOW_ETHERNET_H
#define SWALLOW_ETHERNET_H

#include <xs1.h>
#include "ptr.h"

struct mii_tx {
  clock clk_mii_tx;               /**< MII TX Clock Block **/
  in port p_mii_txclk;            /**< MII TX clock wire */
  out port p_mii_txen;            /**< MII TX enable wire */
  out buffered port:32 p_mii_txd; /**< MII TX data wire */
};

struct mii_rx {
  clock clk_mii_rx;               /**< MII RX Clock Block **/
  in port p_mii_rxclk;            /**< MII RX clock wire */
  in buffered port:32 p_mii_rxd;  /**< MII RX data wire */
  in port p_mii_rxdv;             /**< MII RX data valid wire */
};

struct ipconfig {
  unsigned mac[2]; /* Our mac address (AA:BB:CC:DD:00:00:EE:FF) */
  unsigned char ip[4]; /* Our IP (reversed: {1,0,168,192}) */
  unsigned char mask[4]; /* Netmask */
};

struct arpcache {
  unsigned populated;
  unsigned pre_checksum;
  unsigned mac[2];
  unsigned char ip[4];
  unsigned char header[34];
};

extern struct ipconfig cfg;
extern struct arpcache arpc;

void swallow_ethernet(struct ipconfig PTREF ipcfg, struct mii_tx PTREF mtx, struct mii_rx PTREF mrx, chanend txapp, chanend rxapp);


#endif //SWALLOW_ETHERNET_H
