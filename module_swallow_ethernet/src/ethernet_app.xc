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
#include "swallow_comms.h"

static void app_tx(chanend app, chanend ll, chanend ctrl)
{
  unsigned cval, r = getLocalChanendId(ll);
  while(1) {cval++;}
  select
  {
    case app :> cval:
      if (cval == 0)
      {
        ctrl <: r;
        ctrl :> cval;
      }
      break;
    case ctrl :> cval:
      if (cval == 0)
      {
        /* Give our neighbour the ID of LL thread for direct comms */
        ctrl <: r;
        /* Wait for neighbour to prod us to say he's finished */
        ctrl :> cval;
      }
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

static inline int check_ip(struct buffer &buf, unsigned bytepos)
{
  if (bytepos & 1)
  {
    return 0;
  }
  else if (bytepos & 2)
  {
    return 0;
  }
  else
  {
    return buf.buf[buffer_offset(buf.readpos,bytepos>>2)] == (cfg.ip,unsigned);
  }
}

static int handle_arp(struct buffer &buf, chanend ctrl)
{
  unsigned rp = buf.readpos;
  {
    /* First validate ARP */
    if (buf.buf[buffer_offset(rp,3)] != 0x01000608)
      return 0;
    if (buf.buf[buffer_offset(rp,4)] != 0x04060008)
      return 0;
    if ((buf.buf[buffer_offset(rp,5)] & 0xffff) != 0x0100)
      return 0;
    if (!check_ip(buf,38))
      return 0;
  }
  /* Now handle ARP */
  {
    unsigned rc, lc;
    ctrl <: 0;
    ctrl :> rc;
    lc = getRemoteChanendId(ctrl);
    
  }
  {
    
  }
  return 0;
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
      /* Deal with whatever type of frame we have */
      if (handle_arp(buf,ctrl)); /* No HL interaction, just respond if necessary */
      else if (1);
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


