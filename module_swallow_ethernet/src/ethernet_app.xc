/*
 * ethernet_app - "Application layer" thread
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

#include <print.h>
#include <xclib.h>
#include "ethernet_app.h"
#include "swallow_ethernet.h"
#include "ptr.h"
#include "buffer.h"

static void app_tx(chanend app, chanend ll, chanend ctrl)
{
  unsigned cval;
  while(1) {cval++;}
  select
  {
    case app :> cval:
      break;
    case ctrl :> cval:
      break;
  }
  return;
}

static inline int is_broadcast(struct buffer &buf)
{
  unsigned rp = buf.readpos;
  /* Check the first word in one shot, then the next two bytes in another if necessary */
  if (buf.buf[rp] != 0xffffffff) return 0;
  else return buf.buf[++rp&(BUFFER_WORDS-1)] >> 16 == 0xffff;
}

static inline int is_mac(struct buffer &buf)
{
  unsigned rp = buf.readpos;
  /* Check the first word in one shot, then the next two bytes in another if necessary */
  if (buf.buf[rp] != cfg.mac[0]) return 0;
  else return buf.buf[++rp&(BUFFER_WORDS-1)] >> 16 == cfg.mac[1];
}

static void app_rx(struct buffer &buf, chanend app, chanend ll, chanend ctrl)
{
  int size;
  ll <: 0;
  ll :> size;
  size >>= 2;
  while(size > 0)
  {
    if (is_broadcast(buf) || is_mac(buf))
    {
      //Do something...
    }
    buf.readpos = (buf.readpos + size) & (BUFFER_WORDS-1);
    ll <: size;
    ll :> size;
    size >>= 2;
  }
  return;
}

void ethernet_app_xc(struct buffer &buf, chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl)
{
  chan appctrl;
  par
  {
    app_rx(buf,rxapp,rxctrl,appctrl);
    app_tx(txapp,txctrl,appctrl);
  }
  return;
}


