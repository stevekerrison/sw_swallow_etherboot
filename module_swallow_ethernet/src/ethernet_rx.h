/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef ETHERNET_RX_H
#define ETHERNET_RX_H

#include "swallow_ethernet.h"
#include "ptr.h"
#include "buffer.h"


void ethernet_rx(struct buffer PTREF buf, struct mii_rx PTREF mii, chanend ctrl);


#endif //ETHERNET_RX_H
