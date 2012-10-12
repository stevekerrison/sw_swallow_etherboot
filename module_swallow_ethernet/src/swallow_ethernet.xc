/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

#include <platform.h>
#include "swallow_ethernet.h"
#include "ethernet_rx.h"
#include "buffer.h"

struct buffer rxbuf;
struct buffer txbuf;

void swallow_ethernet(struct mii_if &mii)
{
  chan rxctrl, txctrl, appctrl, rxapp, txapp;
  buffer_init(rxbuf);
  buffer_init(txbuf);
  par
  {
    ethernet_rx(rxbuf,mii,rxctrl);
  }
  return;
}
