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
#include <xclib.h>
#include "swallow_ethernet.h"
#include "ethernet_rx.h"
#include "ethernet_tx.h"
#include "ethernet_app.h"
#include "buffer.h"

struct buffer rxbuf;
struct buffer txbuf;
struct ipconfig cfg;
struct arpcache arpc; /* A single-entry ARP table because we only really want to talk to one thing */

void swallow_ethernet(struct ipconfig &ipcfg, struct mii_tx &mtx, struct mii_rx &mrx, chanend txapp, chanend rxapp)
{
  chan rxctrl, txctrl;
  unsigned rxbufptr = buffer_ptr(rxbuf);
  unsigned txbufptr = buffer_ptr(txbuf);
  buffer_init(rxbuf);
  buffer_init(txbuf);
  cfg = ipcfg;
  arpc.populated = 0;
  {
    char tmp;
    (cfg.ip,unsigned) = byterev((cfg.ip,unsigned));
    tmp = cfg.ip[0];
    cfg.ip[0] = cfg.ip[1];
    cfg.ip[1] = tmp;
    tmp = cfg.ip[2];
    cfg.ip[2] = cfg.ip[3];
    cfg.ip[3] = tmp;
  }
  par
  {
    ethernet_rx(rxbuf,mrx,rxctrl);
    ethernet_tx(txbuf,mtx,txctrl);
    ethernet_app(txbufptr,rxbufptr,txapp,rxapp,txctrl,rxctrl);
  }
  return;
}
