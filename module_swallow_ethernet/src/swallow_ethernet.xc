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
#include "ethernet_tx.h"
#include "ethernet_app.h"
#include "buffer.h"

struct buffer rxbuf;
struct ipconfig cfg;

void swallow_ethernet(struct ipconfig &ipcfg, struct mii_tx &mtx, struct mii_rx &mrx, chanend txapp, chanend rxapp)
{
  chan rxctrl, txctrl;
  unsigned bufptr = buffer_ptr(rxbuf);
  buffer_init(rxbuf);
  cfg = ipcfg;
  par
  {
    ethernet_rx(rxbuf,mrx,rxctrl);
    ethernet_tx(mtx,txctrl);
    ethernet_app(bufptr,txapp,rxapp,txctrl,rxctrl);
  }
  return;
}
