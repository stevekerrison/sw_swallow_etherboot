/*
 * ethernet_tx - Transmit ethernet data
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
#include "swallow_ethernet.h"
#include "buffer.h"
#include "ethernet_tx.h"

static void ethernet_tx_init(struct mii_tx &m)
{
  set_port_use_on(m.p_mii_txclk);
	set_port_use_on(m.p_mii_txd);
	set_port_use_on(m.p_mii_txen);
	set_pad_delay(m.p_mii_txclk, 0);
	m.p_mii_txd <: 0;
	m.p_mii_txen <: 0;
	sync(m.p_mii_txd);
	sync(m.p_mii_txen);
	set_port_strobed(m.p_mii_txd);
	set_port_master(m.p_mii_txd);
	clearbuf(m.p_mii_txd);
	set_port_ready_src(m.p_mii_txen, m.p_mii_txd);
	set_port_mode_ready(m.p_mii_txen);
	set_clock_on(m.clk_mii_tx);
	set_clock_src(m.clk_mii_tx, m.p_mii_txclk);
	set_port_clock(m.p_mii_txd, m.clk_mii_tx);
	set_port_clock(m.p_mii_txen, m.clk_mii_tx);
	set_clock_fall_delay(m.clk_mii_tx, 7);
	start_clock(m.clk_mii_tx);
	clearbuf(m.p_mii_txd);
}

static void tx(struct mii_tx &mii, unsigned size, unsigned pkt[])
{
  register const unsigned poly = 0xEDB88320;
  unsigned words = size >> 2, tail = size & 3, i = 1, crc = 0, word;
  mii.p_mii_txd <: 0x55555555;
	mii.p_mii_txd <: 0x55555555;
	mii.p_mii_txd <: 0xD5555555;
	word = pkt[0];
	mii.p_mii_txd <: word;
	crc32(crc, ~word, poly);
	do {
	  word = pkt[i++];
		crc32(crc, word, poly);
		mii.p_mii_txd <: word;
	} while (i < words);
  switch(tail)
  {
  case 0:
		crc32(crc, 0, poly);
		crc = ~crc;
		mii.p_mii_txd <: crc;
		break;
	case 1:
	  word = pkt[i];
		crc8shr(crc, word, poly);
		partout(mii.p_mii_txd, 8, word);
		crc32(crc, 0, poly);
		crc = ~crc;
		mii.p_mii_txd <: crc;
		break;
	case 2:
	  word = pkt[i];
		partout(mii.p_mii_txd, 16, word);
		word = crc8shr(crc, word, poly);
		crc8shr(crc, word, poly);
		crc32(crc, 0, poly);
		crc = ~crc;
		mii.p_mii_txd <: crc;
		break;
	case 3:
		word = pkt[i];
		partout(mii.p_mii_txd, 24, word);
		word = crc8shr(crc, word, poly);
		word = crc8shr(crc, word, poly);
		crc8shr(crc, word, poly);
		crc32(crc, 0, poly);
		crc = ~crc;
		mii.p_mii_txd <: crc;
		break;
  }
  return;
}
 
void ethernet_tx(struct mii_tx &mii, chanend ctrl)
{
  timer t;
  unsigned size, pkt[380], i, tv;
  t :> tv;
  ethernet_tx_init(mii);
  while(1)
  {
    ctrl :> size;
    t when timerafter(tv) :> void;
    slave {
      for (i = 0; i < size; i += 1)
      {
        ctrl :> pkt[i];
      }
    }
    tx(mii,size,pkt);
    t :> tv;
    tv += 156;
  }
}
