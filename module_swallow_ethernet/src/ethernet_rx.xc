/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (c) 2011, XMOS Ltd., All rights reserved
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

#include <assert.h>
#include <print.h>
#include <xclib.h>
#include "swallow_ethernet.h"
#include "buffer.h"
#include "ethernet_rx.h"

static void ethernet_rx_init(struct mii_rx &m)
{
  set_port_use_on(m.p_mii_rxclk);
  m.p_mii_rxclk :> int _;
	set_port_use_on(m.p_mii_rxd);
	set_port_use_on(m.p_mii_rxdv);
	set_pad_delay(m.p_mii_rxclk, 0);
	set_port_strobed(m.p_mii_rxd);
	set_port_slave(m.p_mii_rxd);
	set_clock_on(m.clk_mii_rx);
	set_clock_src(m.clk_mii_rx, m.p_mii_rxclk);
	set_clock_ready_src(m.clk_mii_rx, m.p_mii_rxdv);
	set_port_clock(m.p_mii_rxd, m.clk_mii_rx);
	set_port_clock(m.p_mii_rxdv, m.clk_mii_rx);
	set_clock_rise_delay(m.clk_mii_rx, 0);
	start_clock(m.clk_mii_rx);
	clearbuf(m.p_mii_rxd);
	return;
}

#pragma unsafe arrays
int rx(struct buffer &buf, struct mii_rx &mii, chanend ctrl)
{
  unsigned start = buf.writepos, taillen, size;
  register unsigned poly = 0xEDB88320, crc = 0x9226F562, word, wp = start, mask = BUFFER_WORDS-1, loop = 1;

  while(loop)
  {
    select
    {
      case mii.p_mii_rxd :> word:
        buf.buf[wp++] = word;
        wp &= mask;
        crc32(crc, word, poly);
        break;
      case mii.p_mii_rxdv when pinseq(0) :> int _:
        loop = 0;
        break;
    }
  }
  taillen = endin(mii.p_mii_rxd);
  mii.p_mii_rxd :> word;
  word >>= (32 - taillen);
  buf.buf[wp++] = word;
  wp &= mask;
  if (buf.writepos < start)
  {
    size = (mask-start)+wp;
  }
  else
  {
    size = wp - start;
  }
  switch (taillen >> 3)
  {
    case 4:
      crc32(crc,word,poly);
      break;
    #pragma fallthrough
    case 3:
      word = crc8shr(crc, word, poly);
    #pragma fallthrough
    case 2:
      word = crc8shr(crc, word, poly);
    #pragma fallthrough
    case 1:
      word = crc8shr(crc, word, poly);
    default:
      break;
  }
  if (~crc)
  {
    printstr("DISCARD ");
    printhex(crc);
    printchar(' ');
    printintln(taillen);
    return -1;
  }
  buf.writepos = wp;
  buf.free -= size;
  assert(buf.free >= 0);
  size <<= 2; /* Multiply by 4 */
  size -= (4-taillen);
  buf.slots_used++;
  return size; /* In bytes */
}

void ethernet_rx(struct buffer &buf, struct mii_rx &mii, chanend ctrl)
{
  unsigned ctrlval, waiting = 0;
  unsigned hasRoom = buf.free >= BUFFER_MINFREE;
  int size = 0;
  ethernet_rx_init(mii);
  mii.p_mii_rxdv when pinseq(0) :> int _;
  while(1)
  {
    select
    {
      case ctrl :> ctrlval:
        if (ctrlval > 0)
        {
          buf.free -= ctrlval;
          buf.slots_used--;
          assert(buf.free >= 0 && buf.slots_used >= 0);
          hasRoom = buf.free >= BUFFER_MINFREE;
        }
        if (buf.slots_used > 0)
        {
          ctrl <: size;
          waiting = 0;
        }
        else
        {
          waiting = 1;
        }
        size = 0;
        break;
      case mii.p_mii_rxd when pinseq(0xD) :> int _:
        if (!hasRoom)
        {
          mii.p_mii_rxdv when pinseq(0) :> int _;
			    clearbuf(mii.p_mii_rxd);
			    break;
        }
        size = rx(buf,mii,ctrl);
        if (size && waiting)
        {
          ctrl <: size;
          waiting = 0;
        }
        break;
    }
  }
  return;
}
