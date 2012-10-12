/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

#include <assert.h>
#include <print.h>
#include "swallow_ethernet.h"
#include "buffer.h"
#include "ethernet_rx.h"

static void ethernet_rx_init(struct mii_if &m)
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

inline int rx(struct buffer &buf, struct mii_if &mii, chanend ctrl)
{
  unsigned poly = 0xEDB88320, crc = 0x9226F562, word, start = buf.writepos, loop = 1, taillen, size;
  while(loop)
  {
    select
    {
      case mii.p_mii_rxd :> word:
        buf.buf[buf.writepos] = word;
        buf.writepos = (buf.writepos+1) & (BUFFER_WORDS-1);
        crc32(crc, word, poly);
        break;
      case mii.p_mii_rxdv when pinseq(0) :> int _:
        loop = 0;
        break;
    }
  }
  taillen = endin(mii.p_mii_rxd) >> 4;
  mii.p_mii_rxd :> word;
  buf.buf[buf.writepos] = word;
  buf.writepos = (buf.writepos+1) & (BUFFER_WORDS-1);
  if (buf.writepos < start)
  {
    size = (BUFFER_WORDS-1-start)+buf.writepos;
  }
  else
  {
    size = buf.writepos - start;
  }
  if (taillen == 4)
  {
    crc32(crc,word,poly);
  }
  else
  {
    switch (taillen)
    {
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
  }
  if (~crc)
  {
    buf.writepos = start;
    return -1;
  }
  buf.free -= size;
  assert(buf.free >= 0);
  size <<= 2; /* Multiply by 4 */
  size -= (4-taillen);
  return size; /* In bytes */
}

void ethernet_rx(struct buffer &buf, struct mii_if &mii, chanend ctrl)
{
  unsigned ctrlval;
  unsigned hasRoom = buf.free >= BUFFER_MINFREE;
  int size = 0;
  ethernet_rx_init(mii);
  mii.p_mii_rxdv when pinseq(0) :> int _;
  while(1)
  {
    select
    {
      case ctrl :> ctrlval:
        buf.free -= ctrlval;
        assert(buf.free >= 0);
        hasRoom = buf.free >= BUFFER_MINFREE;
        ctrl <: size;
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
        break;
    }
  }
  return;
}
