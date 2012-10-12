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

struct mii_if {
    clock clk_mii_rx;               /**< MII RX Clock Block **/
    clock clk_mii_tx;               /**< MII TX Clock Block **/
    
    in port p_mii_rxclk;            /**< MII RX clock wire */
    in port p_mii_rxer;             /**< MII RX error wire */
    in buffered port:32 p_mii_rxd;  /**< MII RX data wire */
    in port p_mii_rxdv;             /**< MII RX data valid wire */
    
    in port p_mii_txclk;            /**< MII TX clock wire */
    out port p_mii_txen;            /**< MII TX enable wire */
    out buffered port:32 p_mii_txd; /**< MII TX data wire */
};

void swallow_ethernet(struct mii_if PTREF mii);


#endif //SWALLOW_ETHERNET_H
