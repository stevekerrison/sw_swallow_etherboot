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
#include <assert.h>
#include "ethernet_app.h"
#include "swallow_ethernet.h"
#include "ptr.h"
#include "buffer.h"
#include "swallow_comms.h"

static void app_tx(struct buffer &buf, chanend app, chanend ll, chanend ctrl)
{
  unsigned cval, r = getLocalChanendId(ll);
  unsigned hasRoom = buf.free >= BUFFER_MINFREE, waiting = 0, llval, size;
  while (1)
  {
    #pragma ordered
    select
    {
      case ll :> llval:
        if (llval > 0)
        {
          printstrln("PACKET CLEARED");
          buf.free += (llval>>2)+((llval & 3) != 0);
          buf.slots_used--;
          assert(buf.free >= 0 && buf.slots_used >= 0);
        }
        if (buf.slots_used > 0)
        {
          unsigned size = buf.buf[buf.readpos];
          buffer_incpos(buf.readpos,1);
          ll <: size;
          waiting = 0;
        }
        else
        {
          printstrln("WAITING...");
          waiting = 1;
        }
        assert(hasRoom || buf.slots_used > 0);
        break;
      case ctrl :> cval:
        printstrln("REQ FROM RX THREAD");
        printintln(buf.writepos);
        size = cval;
        if (cval == 1)
        {
          printintln(buf.free);
          size = 42;
        }
        hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
        while (!hasRoom)
        {
          printstrln("AINT GOT NO ROOM!");
          ll :> llval;
          if (llval > 0)
          {
            buf.free += (llval>>2)+((llval & 3) != 0);
            buf.slots_used--;
            assert(buf.free >= 0 && buf.slots_used >= 0);
          }
          if (buf.slots_used > 0)
          {
            unsigned size = buf.buf[buf.readpos];
            buffer_incpos(buf.readpos,1);
            ll <: size;
            waiting = 0;
          }
          hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
          assert(hasRoom || buf.slots_used > 0);
        }
        if (cval == 1) 
        {
          /* ARP response! */
          int i;
          char c;
          unsigned word;
          buf.slots_used++;
          buf.free -= (size>>2)+((size & 3) != 0);
          buf.buf[buf.writepos] = size;
          buffer_incpos(buf.writepos,1);
          slave {
            for (i = 0; i < 6; i += 1)
            {
              ctrl :> c;
              buffer_set_byte(buf.buf,buf.writepos,i,c);
              buffer_set_byte(buf.buf,buf.writepos,32+i,c);
            }
            ctrl :> word;
          }
          for (i = 38; i < 42; i += 1)
          {
            buffer_set_byte(buf.buf,buf.writepos,i,word & 0xff);
            word >>= 8;
          }
          buffer_set_byte(buf.buf,buf.writepos,28,cfg.ip[2]);
          buffer_set_byte(buf.buf,buf.writepos,29,cfg.ip[3]);
          buffer_set_byte(buf.buf,buf.writepos,30,cfg.ip[0]);
          buffer_set_byte(buf.buf,buf.writepos,31,cfg.ip[1]);
          for (i = 0; i < 4; i += 1)
          {
            buffer_set_byte(buf.buf,buf.writepos,22+i,(cfg.mac[0],char[])[3-i]);
            buffer_set_byte(buf.buf,buf.writepos,6+i,(cfg.mac[0],char[])[3-i]);
          }
          buffer_set_byte(buf.buf,buf.writepos,26,(cfg.mac[1],char[])[3]);
          buffer_set_byte(buf.buf,buf.writepos,10,(cfg.mac[1],char[])[3]);
          buffer_set_byte(buf.buf,buf.writepos,27,(cfg.mac[1],char[])[2]);
          buffer_set_byte(buf.buf,buf.writepos,11,(cfg.mac[1],char[])[2]);
          buf.buf[buffer_offset(buf.writepos,3)] = 0x01000608;
          buf.buf[buffer_offset(buf.writepos,4)] = 0x04060008;
          buffer_set_byte(buf.buf,buf.writepos,20,0x0);
          buffer_set_byte(buf.buf,buf.writepos,21,0x2);
          buffer_incpos(buf.writepos,(size>>2)+((size & 3) != 0));
        }
        if (waiting)
        {
          buffer_incpos(buf.readpos,1);
          ll <: size;
        }
        break;
      case app :> cval:
        if (cval == 0)
        {
          ctrl <: r;
          ctrl :> cval;
        }
        break;
    }
  }
  return;
}

static inline int is_broadcast(struct buffer &buf)
{
  unsigned rp = buf.readpos;
  /* Check the first word in one shot, then the next two bytes in another if necessary */
  if (buf.buf[rp] != 0xffffffff) return 0;
  else return (buf.buf[++rp&(BUFFER_WORDS-1)] & 0xffff) == 0xffff;
}

static inline int is_mac(struct buffer &buf)
{
  unsigned rp = buf.readpos;
  /* Check the first word in one shot, then the next two bytes in another if necessary */
  if (byterev(buf.buf[rp]) != cfg.mac[0]) return 0;
  else return (byterev(buf.buf[++rp&(BUFFER_WORDS-1)]) & 0xffff0000) == cfg.mac[1];
}

static inline int check_ip(struct buffer &buf, unsigned bytepos)
{
  unsigned ip = buf.buf[buffer_offset(buf.readpos,bytepos>>2)];
  if (bytepos & 3) /* Unaligned */
  {
    unsigned ipb = buf.buf[buffer_offset(buf.readpos,(bytepos>>2)+1)];
    switch (bytepos & 3)
    {
    case 1:
      ip = (ip & 0xffffff00) | (ipb & 0x000000ff);
      break;
    case 2:
      ip = (ip & 0xffff0000) | (ipb & 0x0000ffff);
      break;
    case 3:
      ip = (ip & 0xff000000) | (ipb & 0x00ffffff);
      break;
    }
  }
  return ip == (cfg.ip,unsigned);
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
    int i;
    ctrl <: 1;
    master {
      for (i = 22; i < 28; i += 1)
      {
        ctrl <: buffer_get_byte(buf,rp,i);
      }
      ctrl <: buf.buf[buffer_offset(rp,7)];
    }
    printstrln("ARP HANDLED IN RX");
  }
  return 0;
}

static void app_rx(struct buffer &buf, chanend app, chanend ll, chanend ctrl)
{
  int size;
  ll <: 0;
  ll :> size;
  while(size > 0)
  {
    if (is_broadcast(buf) || is_mac(buf))
    {
      /* Deal with whatever type of frame we have */
      if (handle_arp(buf,ctrl)); /* No HL interaction, just respond if necessary */
      else if (1);
    }
    buf.readpos = (buf.readpos + (size>>2) + ((size & 3) != 0)) & (BUFFER_WORDS-1);
    ll <: size;
    ll :> size;
  }
  printstrln("RX EXIT");
  return;
}

void ethernet_app_xc(struct buffer &txbuf, struct buffer &rxbuf, chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl)
{
  chan appctrl;
  par
  {
    app_rx(rxbuf,rxapp,rxctrl,appctrl);
    app_tx(txbuf,txapp,txctrl,appctrl);
  }
  return;
}


