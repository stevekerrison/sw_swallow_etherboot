/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef ETHERNET_TX_H
#define ETHERNET_TX_H

#include "swallow_ethernet.h"
#include "ptr.h"
#include "buffer.h"

void ethernet_tx(struct mii_tx PTREF mii, chanend ctrl);


#endif //ETHERNET_TX_H
