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
#include "swallow_ethernet.h"
#include "swallow_comms.h"
#include "ethernet.h"
#include "checksum.h"
#include "xscope.h"

#define SENDING 0x4
#define RECEIVING 0x8
#define WAITING 0x2
#define IDLE 0x1

#define RRQ   1
#define WRQ   2
#define DATA  3
#define ACK   4
#define ERROR 5

#define MAX(x,y) ((x < y) ? y : x)

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

void swallow_tftp_server(unsigned char rxbuf[], unsigned char txbuf[], unsigned udp_len, chanend tx)
{
  static unsigned state = IDLE;
  unsigned opcode = (rxbuf[42] << 8) | rxbuf[43];
  unsigned ip_checksum, tx_frame_size = 20, tx_udp_len = 8, txbytes;
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
      txbuf[42] = 0;
      txbuf[43] = DATA;
      txbuf[44] = 0;
      txbuf[45] = 1;
      txbuf[46] = 'a';
      txbytes = prep_header(txbuf,5);
      mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
    }
  }
  return;
}
