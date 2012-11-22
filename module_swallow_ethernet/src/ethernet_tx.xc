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

static void tx(struct buffer &buf, struct mii_tx &mii, unsigned size)
{
  register const unsigned poly = 0xEDB88320;
  unsigned rp = buf.readpos;
  unsigned words = size >> 2, tail = size & 3, i = 1, crc = 0, word;
  /*printstrln("TX!");
  printintln(size);*/
  /*for (i = 0; i < size; i += 4)
  {
    printhex(buf.buf[rp]);
    printchar(' ');
    buffer_incpos(rp,1)
  }
  printchar('\n');
  i = 1;*/
  rp = buf.readpos;
  mii.p_mii_txd <: 0x55555555;
	mii.p_mii_txd <: 0x55555555;
	mii.p_mii_txd <: 0xD5555555;
	word = buf.buf[rp];
	buffer_incpos(rp,1)
	mii.p_mii_txd <: word;
	crc32(crc, ~word, poly);
	do {
	  word = buf.buf[rp];
	  buffer_incpos(rp,1);
		crc32(crc, word, poly);
		mii.p_mii_txd <: word;
	} while (i++ < words);
	if (size < 52)
	{
	  unsigned mask;
	  switch (tail)
	  {
	    case 0:
	      break;
	    case 1:
	      mask = 0xff;
	      break;
	    case 2:
	      mask = 0xffff;
	      break;
	    case 3:
	      mask = 0xffffff;
	      break;
	  }
	  word = buf.buf[rp] & mask;
	  crc32(crc, word, poly);
		mii.p_mii_txd <: word;
	  for (i = words*4; i < 52; i += 4)
	  {
	    crc32(crc, 0, poly);
		  mii.p_mii_txd <: 0;
	  }
	}
	else
	{
    switch(tail)
    {
    case 0:
		  
		  break;
	  case 1:
	    word = buf.buf[rp];
		  crc8shr(crc, word, poly);
		  partout(mii.p_mii_txd, 8, word);
		  break;
	  case 2:
	    word = buf.buf[rp];
		  partout(mii.p_mii_txd, 16, word);
		  word = crc8shr(crc, word, poly);
		  crc8shr(crc, word, poly);
		  break;
	  case 3:
		  word = buf.buf[rp];
		  partout(mii.p_mii_txd, 24, word);
		  word = crc8shr(crc, word, poly);
		  word = crc8shr(crc, word, poly);
		  crc8shr(crc, word, poly);
		  break;
    }
  }
  crc32(crc, 0, poly);
  crc = ~crc;
  mii.p_mii_txd <: crc;
  return;
}
 
void ethernet_tx(struct buffer &buf, struct mii_tx &mii, chanend ctrl)
{
  timer t;
  unsigned size, i, tv;
  ethernet_tx_init(mii);
  t :> tv;
  ctrl <: 0;
  ctrl :> size;
  while(size > 0)
  {
    t when timerafter(tv) :> void;
    tx(buf,mii,size);
    t :> tv;
    tv += 156;
    ctrl <: size;
    ctrl :> size;
  }
  printstrln("TX EXIT");
  return;
}
