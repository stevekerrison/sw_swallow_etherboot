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

static void app_rx(struct buffer &buf, chanend app, chanend ll, chanend ctrl)
{
  int size,i;
  ll <: 0;
  ll :> size;
  size >>= 2;
  while(size > 0)
  {
    printintln(size);
    for (i = 0; i < size; i += 1)
    {
      printhex(byterev(buf.buf[i]));
      printchar(' ');
    }
    printcharln('\n');
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


