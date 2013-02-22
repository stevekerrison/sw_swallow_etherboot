/*
 * swallow_tftp_server - SFTP serer for booting the Swallow grid
 *
 * Copyright (C) 2013 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include <platform.h>
#include <stdlib.h>
#include <stdio.h>
#include "swallow_ethernet.h"
#include "swallow_comms.h"
#include "ethernet.h"
#include "checksum.h"
#include "xscope.h"

#define SENDING 0x4
#define RECEIVING 0x8
#define WAITING 0x2
#define IDLE 0x1

#define READY 0x1
#define BOOTING 0x2
#define DISCARD 0x4

#define RRQ   1
#define WRQ   2
#define DATA  3
#define ACK   4
#define ERROR 5

#define MAX(x,y) ((x < y) ? y : x)

unsigned char cfg_str[8];

static void copy_header(unsigned char rxbuf[], unsigned char txbuf[], unsigned udp_len)
{
  udp_len += 38;
  for (int i = 0; i < 6; i++)
  {
    txbuf[i] = rxbuf[6+i];
    txbuf[6+i] = rxbuf[i];
  }
  for (int i = 12; i < 24; i += 1)
  {
    txbuf[i] = rxbuf[i];
  }
  txbuf[24] = 0;
  txbuf[25] = 0;
  for (int i = 26; i < 30; i += 1)
  {
    txbuf[i] = rxbuf[4+i];
    txbuf[4+i] = rxbuf[i];
  }
  txbuf[34] = rxbuf[36];
  txbuf[35] = rxbuf[37];
  txbuf[36] = rxbuf[34];
  txbuf[37] = rxbuf[35];
  for (int i = 38; i < 40; i += 1)
  {
    txbuf[i] = rxbuf[i];
  }
  txbuf[40] = 0;
  txbuf[41] = 0;
  txbuf[38] = 0;
  txbuf[39] = 8;
  txbuf[17] = 20;
  return;
}

unsigned prep_header(unsigned char txbuf[], unsigned payload_len)
{
  unsigned udp_len = 8 + payload_len, frame_size = 20 + udp_len;
  unsigned ip_checksum;
  txbuf[38] = udp_len >> 8;
  txbuf[39] = udp_len & 0xff;
  txbuf[16] = frame_size >> 8;
  txbuf[17] = frame_size & 0xff;
  ip_checksum = checksum_ip(txbuf);
  txbuf[24] = ip_checksum >> 8;
  txbuf[25] = ip_checksum & 0xff;
  return MAX(60,frame_size + 14);
}

void swallow_tftp_init_cfgstr(struct swallow_xlinkboot_cfg &cfg)
{
  unsigned char boards_w[4], boards_h[4];
  unsigned j;
  sprintf(boards_w,"%u",cfg.boards_w);
  sprintf(boards_h,"%u",cfg.boards_h);
  for (int i = 0; i < 4; i += 1)
  {
    if (boards_w[i] == '\0')
    {
      cfg_str[i] = ',';
      j = i+1;
      break;
    }
    cfg_str[i] = boards_w[i];
  }
  for (int i = 0; i < 4; i += 1)
  {
    cfg_str[j++] = boards_h[i];
    if (boards_h[i] == '\0')
      break;
  }
  return;
}

static int swallow_tftp_boot(unsigned char rxbuf[], unsigned udp_len, struct swallow_xlinkboot_cfg &cfg)
{
  static unsigned state = READY;
  static unsigned cores, block, word, node, ce;
  if (state == READY)
  {
    unsigned newblock = (rxbuf[44] << 8) | rxbuf[45];
    unsigned opcode = (rxbuf[42] << 8) | rxbuf[43];
    if (opcode != DATA || newblock != block + 1)
    {
      return -4;
    }
    block += 1;
    if (cores > ((rxbuf[47] << 8) | rxbuf[48]))
    {
      return -3;
    }
    if (rxbuf[46] == 1)
    {
      swallow_xlinkboot(cfg.boards_w,cfg.boards_h,1,cfg.position,cfg.PLL,cfg.PLL_len,cfg.reset_port);
    }
    word = rxbuf[49];
    word <<= 8;
    word |= rxbuf[50];
    word <<= 8;
    word |= rxbuf[51];
    word <<= 8;
    word |= rxbuf[52];
    //TODO: Now get a channel end
    streamOutWord(ce,node);
    streamOutWord(ce,word);
    for (int i = 53; i < udp_len + 34; i += 1)
    {
      for (int j = 0; j < 4; j += 1)
      {
        word <<= 8;
        word |= rxbuf[j];
      }
      streamOutWord(ce,word);
    }
  }
  return 0;
}

void swallow_tftp_server(unsigned char rxbuf[], unsigned char txbuf[], unsigned udp_len, chanend tx,
  struct swallow_xlinkboot_cfg &cfg)
{
  int boot_result;
  static unsigned state = IDLE;
  unsigned opcode = (rxbuf[42] << 8) | rxbuf[43];
  unsigned txbytes;
  copy_header(rxbuf,txbuf, udp_len);
  if (state & IDLE)
  {
    if (state != IDLE)
    {
      //No idea how we ended up here, reset SM
      state = IDLE;
      return;
    }
    if (opcode == RRQ)
    {
      unsigned i = 0;
      txbuf[42] = 0;
      txbuf[43] = DATA;
      txbuf[44] = 0;
      txbuf[45] = 1;
      while(cfg_str[i] != '\0')
      {
        txbuf[46+i] = cfg_str[i];
        i++;
      }
      txbuf[46+i] = '\n';
      txbytes = prep_header(txbuf,i+4);
      mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
      //TODO: Handle the ACK that comes back from this RRQ
    }
    else if (opcode == WRQ)
    {
      state = RECEIVING;
      txbuf[42] = 0;
      txbuf[43] = ACK;
      txbuf[44] = 0;
      txbuf[45] = 0;
      txbytes = prep_header(txbuf,4);
      mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
    }
  }
  else if (state & RECEIVING)
  {
    if (state != RECEIVING)
    {
      //No other state bits allowed just yet
      state = IDLE;
      return;
    }
    if ((boot_result = swallow_tftp_boot(rxbuf, udp_len, cfg)) < 0)
    {
      txbuf[42] = 0;
      txbuf[43] = ACK;
      txbuf[44] = 0;
      txbuf[45] = 0;
      //If the data packet isn't full, then we're done!
      if (udp_len < 512 + 4 + 8)
      {
        state = IDLE;
      }
      txbytes = prep_header(txbuf,4);
    }
    else
    {
      txbuf[42] = 0;
      txbuf[43] = ACK;
      txbuf[44] = 0;
      txbuf[45] = -boot_result;
      txbuf[46] = '\0';
      txbytes = prep_header(txbuf,5);
    }
    mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
    
    
  }
  return;
}
