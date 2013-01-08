/*
 * swallow_ethernet - "Application layer" thread
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
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

unsigned char ethertype_ip[] = {0x08, 0x00};
unsigned char ethertype_arp[] = {0x08, 0x06};
unsigned char own_mac_addr[6];

#pragma unsafe arrays
int is_ethertype(unsigned char data[], unsigned char type[]){
	int i = 12;
	return data[i] == type[0] && data[i + 1] == type[1];
}

#pragma unsafe arrays
int is_mac_addr(unsigned char data[], unsigned char addr[]){
	for (int i=0;i<6;i++){
          if (data[i] != addr[i]){
			return 0;
		}
	}

	return 1;
}

#pragma unsafe arrays
int is_broadcast(unsigned char data[]){
	for (int i=0;i<6;i++){
          if (data[i] != 0xFF){
			return 0;
		}
	}

	return 1;
}

//::custom-filter
int mac_custom_filter(unsigned int data[]){
	if (is_ethertype((data,char[]), ethertype_arp)){
		return 1;
	}else if (is_ethertype((data,char[]), ethertype_ip)){
		return 1;
	}

	return 0;
}
//::


int build_arp_response(unsigned char rxbuf[], unsigned int txbuf[], const unsigned char own_mac_addr[6])
{
  unsigned word;
  unsigned char byte;
  const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;

  for (int i = 0; i < 6; i++)
    {
      byte = rxbuf[22+i];
      (txbuf, unsigned char[])[i] = byte;
      (txbuf, unsigned char[])[32 + i] = byte;
    }
  word = (rxbuf, const unsigned[])[7];
  for (int i = 0; i < 4; i++)
    {
      (txbuf, unsigned char[])[38 + i] = word & 0xFF;
      word >>= 8;
    }

  (txbuf, unsigned char[])[28] = own_ip_addr[0];
  (txbuf, unsigned char[])[29] = own_ip_addr[1];
  (txbuf, unsigned char[])[30] = own_ip_addr[2];
  (txbuf, unsigned char[])[31] = own_ip_addr[3];

  for (int i = 0; i < 6; i++)
  {
    (txbuf, unsigned char[])[22 + i] = own_mac_addr[i];
    (txbuf, unsigned char[])[6 + i] = own_mac_addr[i];
  }
  txbuf[3] = 0x01000608;
  txbuf[4] = 0x04060008;
  (txbuf, unsigned char[])[20] = 0x00;
  (txbuf, unsigned char[])[21] = 0x02;

  // Typically 48 bytes (94 for IPv6)
  for (int i = 42; i < 64; i++)
  {
    (txbuf, unsigned char[])[i] = 0x00;
  }

  return 64;
}


int is_valid_arp_packet(const unsigned char rxbuf[], int nbytes)
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;

  if (rxbuf[12] != 0x08 || rxbuf[13] != 0x06)
    return 0;

  //printstr("ARP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x01000608)
  {
    printstr("Invalid et_htype\n");
    return 0;
  }
  if ((rxbuf, const unsigned[])[4] != 0x04060008)
  {
    printstr("Invalid ptype_hlen\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[5] & 0xFFFF) != 0x0100)
  {
    printstr("Not a request\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[38 + i] != own_ip_addr[i])
    {
      printstr("Not for us\n");
      return 0;
    }
  }

  return 1;
}


int build_icmp_response(unsigned char rxbuf[], unsigned char txbuf[], const unsigned char own_mac_addr[6])
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;
  unsigned icmp_checksum;
  int datalen;
  int totallen;
  const int ttl = 0x40;
  int pad;

  // Precomputed empty IP header checksum (inverted, bytereversed and shifted right)
  unsigned ip_checksum = 0x0185;

  for (int i = 0; i < 6; i++)
    {
      txbuf[i] = rxbuf[6 + i];
    }
  for (int i = 0; i < 4; i++)
    {
      txbuf[30 + i] = rxbuf[26 + i];
    }
  icmp_checksum = byterev((rxbuf, const unsigned[])[9]) >> 16;
  for (int i = 0; i < 4; i++)
    {
      txbuf[38 + i] = rxbuf[38 + i];
    }
  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  datalen = totallen - 28;
  for (int i = 0; i < datalen; i++)
    {
      txbuf[42 + i] = rxbuf[42+i];
    }

  for (int i = 0; i < 6; i++)
  {
    txbuf[6 + i] = own_mac_addr[i];
  }
  (txbuf, unsigned[])[3] = 0x00450008;
  totallen = byterev(28 + datalen) >> 16;
  (txbuf, unsigned[])[4] = totallen;
  ip_checksum += totallen;
  (txbuf, unsigned[])[5] = 0x01000000 | (ttl << 16);
  (txbuf, unsigned[])[6] = 0;
  for (int i = 0; i < 4; i++)
  {
    txbuf[26 + i] = own_ip_addr[i];
  }
  ip_checksum += (own_ip_addr[0] | own_ip_addr[1] << 8);
  ip_checksum += (own_ip_addr[2] | own_ip_addr[3] << 8);
  ip_checksum += txbuf[30] | (txbuf[31] << 8);
  ip_checksum += txbuf[32] | (txbuf[33] << 8);

  txbuf[34] = 0x00;
  txbuf[35] = 0x00;

  icmp_checksum = (icmp_checksum + 0x0800);
  icmp_checksum += icmp_checksum >> 16;
  txbuf[36] = icmp_checksum >> 8;
  txbuf[37] = icmp_checksum & 0xFF;

  while (ip_checksum >> 16)
  {
    ip_checksum = (ip_checksum & 0xFFFF) + (ip_checksum >> 16);
  }
  ip_checksum = byterev(~ip_checksum) >> 16;
  txbuf[24] = ip_checksum >> 8;
  txbuf[25] = ip_checksum & 0xFF;

  for (pad = 42 + datalen; pad < 64; pad++)
  {
    txbuf[pad] = 0x00;
  }
  return pad;
}


int is_valid_icmp_packet(const unsigned char rxbuf[], int nbytes)
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;
  unsigned totallen;


  if (rxbuf[23] != 0x01)
    return 0;

  //printstr("ICMP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x00450008)
  {
    printstr("Invalid et_ver_hdrl_tos\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[8] >> 16) != 0x0008)
  {
    printstr("Invalid type_code\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[30 + i] != own_ip_addr[i])
    {
      printstr("Not for us\n");
      return 0;
    }
  }

  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    printstr("Invalid size\n");
    printintln(nbytes);
    printintln(totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    printstr("Bad checksum\n");
    return 0;
  }

  return 1;
}

unsigned udp_checksum(unsigned short frame[], unsigned pkt_len)
{
  unsigned accum = 0x1100 + frame[19], len = pkt_len >> 1, i;
  printstr("Checksum field is: ");
  printhexln(frame[20]);
  for (i = 13; i < len; i += 1)
  {
    accum += frame[i];
  }
  if (len & 1)
  {
    accum += frame[i] & 0xff;
  }
  while(accum >> 16)
  {
    accum = (accum & 0xffff) + (accum >> 16);
  }
  accum = byterev(~accum) >> 16;
  printhexln(accum);
  return accum;
}

int build_udp_loopback(unsigned char rxbuf[], unsigned char txbuf[], const unsigned char own_mac_addr[6], unsigned len)
{
  len += 38;
  for (int i = 0; i < 6; i++)
  {
    txbuf[i] = rxbuf[6+i];
    txbuf[6+i] = rxbuf[i];
  }
  for (int i = 12; i < 26; i += 1)
  {
    txbuf[i] = rxbuf[i];
  }
  for (int i = 26; i < 30; i += 1)
  {
    txbuf[i] = rxbuf[4+i];
    txbuf[4+i] = rxbuf[i];
  }
  for (int i = 34; i < len; i += 1)
  {
    txbuf[i] = rxbuf[i];
  }
  return 1;
}

int is_valid_udp_packet(const unsigned char rxbuf[], int nbytes)
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;
  unsigned totallen;

  if (rxbuf[23] != 0x11)
    return 0;


  if ((rxbuf, const unsigned[])[3] != 0x00450008)
  {
    printstr("Invalid et_ver_hdrl_tos\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[30 + i] != own_ip_addr[i])
    {
      printstr("Not for us\n");
      return 0;
    }
  }

  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    printstr("Invalid size\n");
    printintln(nbytes);
    printintln(totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    printstr("Bad checksum\n");
    return 0;
  }
  
  /*if (udp_checksum((rxbuf,unsigned short[]),nbytes) != 0)
  {
    printstrln("Bad UDP checksum");
    return 0;
  }*/
  

  return 1;
}

#pragma unsafe arrays
static int handle_udp_5b5b(unsigned char frame[], unsigned frame_size, chanend grid)
{
  unsigned dst, format, len, udp_len;
  if ((frame,unsigned short[])[21] != 0x7ada) //Does UDP payload have "D47A" at the front?
  {
    return 0;
  }
  udp_len = byterev((frame,unsigned short[])[19]) >> 16;
  dst = byterev((frame,unsigned [])[11]);
  format = byterev((frame,unsigned [])[12]);
  len = format & 0x00ffffff;
  format >>= 24;
  if (len > 0 && udp_len - 18 != len * format)
  {
    return 0;
  }
  else if (len == 0)
  {
    len = (udp_len - 18) / format;
  }
  startTransactionClient(grid,dst,format,len);
  if (format == 0x1)
  {
    for (int i = 0; i < len; i += 1)
    {
      streamOutByte(grid,frame[52+i]);
    }
  }
  else if (format == 0x4)
  {
    for (int i = 0; i < len; i += 1)
    {
      streamOutWord(grid,(frame,unsigned [])[13+i]);
    }
  }
  endTransactionClient(grid);
  return 1;
}

void swallow_ethernet(chanend tx, chanend rx, chanend grid_tx, chanend grid_rx)
{
  unsigned int rxbuf[1600/4];
  unsigned int txbuf[1600/4];
  
  //::get-macaddr
  mac_get_macaddr(tx, own_mac_addr);
  //::

  //::setup-filter
#ifdef CONFIG_FULL
  mac_set_custom_filter(rx, 0x1);
#endif
  //::
  printstr("Test started\n");

  //::mainloop
  while (1)
  {
    unsigned int src_port;
    unsigned int nbytes;
    mac_rx(rx, (rxbuf,char[]), nbytes, src_port);
#ifdef CONFIG_LITE
    if (!is_broadcast((rxbuf,char[])) && !is_mac_addr((rxbuf,char[]), own_mac_addr))
      continue;
    if (mac_custom_filter(rxbuf) != 0x1)
      continue;
#endif


   //::arp_packet_check
    if (is_valid_arp_packet((rxbuf,char[]), nbytes))
      {
        build_arp_response((rxbuf,char[]), txbuf, own_mac_addr);
        mac_tx(tx, txbuf, nbytes, ETH_BROADCAST);
        //printstr("ARP response sent\n");
      }
  //::icmp_packet_check  
    else if (is_valid_icmp_packet((rxbuf,char[]), nbytes))
      {
        build_icmp_response((rxbuf,char[]), (txbuf, unsigned char[]), own_mac_addr);
        mac_tx(tx, txbuf, nbytes, ETH_BROADCAST);
        //printstr("ICMP response sent\n");
      }
    else if (is_valid_udp_packet((rxbuf,char[]),nbytes))
    {
      unsigned udp_len = byterev(rxbuf[9]);
      unsigned udp_dst = udp_len >> 16;
      udp_len &= 0xffff;
      switch (udp_dst)
      {
        case 69:      //TFTP
          break;
        case 0x1b1b:  //Loopback test
          build_udp_loopback((rxbuf,char[]), (txbuf, unsigned char[]), own_mac_addr, udp_len);
          mac_tx(tx, txbuf, nbytes, ETH_BROADCAST);
          break;
        case 0x5b5b:  //5wallow Board I/O
          handle_udp_5b5b((rxbuf,char[]), nbytes, grid_tx);
          break;
        default:
          //Nothing to do
          break;
      }
    }
  //::
  }
}

#if 0
#include <print.h>
#include <xclib.h>
#include <assert.h>
#include "ethernet_app.h"
#include "swallow_ethernet.h"
#include "ptr.h"
#include "buffer.h"
#include "swallow_comms.h"

/*
 * Build an Eth/IP header out of an ARP response, where src/dst MAC & IP are ours & theirs.
 * This suits our communication model where the only thing ARPing will be our control PC.
 */
static void build_header_from_arp(struct buffer &buf)
{
  for (int i = 0; i < 3; i += 1)
  {
    (arpc.header,unsigned[])[i] = buf.buf[buffer_offset(buf.writepos,i)];
  }
  (arpc.header,unsigned[])[3] = 0x00450008;
  /*buffer_set_byte(buf.buf,buf.writepos,16,(size-10) >> 8);
  buffer_set_byte(buf.buf,buf.writepos,17,(size-10) & 0xff);*/
  arpc.header[18] = 0;
  arpc.header[19] = 0;
  (arpc.header,unsigned[])[5] = 0x00400000;
  (arpc.header,unsigned[])[6] = 0;
  arpc.header[26] = cfg.ip[2];
  arpc.header[27] = cfg.ip[3];
  arpc.header[28] = cfg.ip[0];
  arpc.header[29] = cfg.ip[1];
  arpc.header[30] = buffer_get_byte(buf.buf,buf.writepos,38);
  arpc.header[31] = buffer_get_byte(buf.buf,buf.writepos,39);
  arpc.header[32] = buffer_get_byte(buf.buf,buf.writepos,40);
  arpc.header[33] = buffer_get_byte(buf.buf,buf.writepos,41);
  /* IP checksum - Pre-calculate as much as we can right now */
  {
    unsigned ip_checksum = 0, i;
    for (i = 14; i < 16; i += 2)
    {
      ip_checksum += arpc.header[i] | (arpc.header[i+1] << 8);
    }
    for (i = 18; i < 22; i += 2)
    {
      ip_checksum += arpc.header[i] | (arpc.header[i+1] << 8);
    }
    for (i = 26; i < 34; i += 2)
    {
      ip_checksum += arpc.header[i] | (arpc.header[i+1] << 8);
    }
    arpc.pre_checksum = ip_checksum;
  }
  arpc.populated = 1;
  return;
}

static inline void ip_build_checksum(struct buffer &buf)
{
  unsigned ip_checksum = arpc.pre_checksum;
  ip_checksum += buffer_get_byte(buf.buf,buf.writepos,16) | (buffer_get_byte(buf.buf,buf.writepos,17) << 8);
  ip_checksum += buffer_get_byte(buf.buf,buf.writepos,22) | (buffer_get_byte(buf.buf,buf.writepos,23) << 8);
  while (ip_checksum >> 16)
  {
    ip_checksum = (ip_checksum & 0xffff) + (ip_checksum >> 16);
  }
  ip_checksum = byterev(~ip_checksum) >> 16;
  buffer_set_byte(buf.buf,buf.writepos,24,ip_checksum >> 8);
  buffer_set_byte(buf.buf,buf.writepos,25,ip_checksum & 0xff);
  return;
}

static void build_arp_out(struct buffer &buf, chanend ctrl, unsigned size)
{
  int i;
  char c;
  unsigned word;
  buf.sizes[buf.sizeposhd].words = (size>>2)+((size & 3) != 0);
  buf.sizes[buf.sizeposhd].bytes = size;
  buffer_incsizepos(buf.sizeposhd,1);
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
  if (!arpc.populated)
  {
    build_header_from_arp(buf);
  }
  buffer_incpos(buf.writepos,(size>>2)+((size & 3) != 0));
  return;
}

static void build_icmp_echo(struct buffer &buf, chanend ctrl, unsigned size)
{
  unsigned datalen, icmp_checksum;
  char b;
  int i;
  buf.sizes[buf.sizeposhd].words = (size>>2)+((size & 3) != 0);
  buf.sizes[buf.sizeposhd].bytes = size;
  buffer_incsizepos(buf.sizeposhd,1);
  slave
  {
    for (i = 38; i < 42; i += 1)
    {
      ctrl :> b;
      buffer_set_byte(buf.buf,buf.writepos,i,b);
    }
    ctrl :> datalen;
    for (i = 42; i < datalen - 28 + 42; i += 1)
    {
      ctrl :> b;
      buffer_set_byte(buf.buf,buf.writepos,i,b);
    }
    ctrl :> icmp_checksum;
  }
  for (i = 0; i < 8; i += 1)
  {
    buf.buf[buffer_offset(buf.writepos,i)] = (arpc.header,unsigned[])[i];
  }
  buffer_set_byte(buf.buf,buf.writepos,32,arpc.header[32]);
  buffer_set_byte(buf.buf,buf.writepos,33,arpc.header[33]);
  buffer_set_byte(buf.buf,buf.writepos,23,0x1);
  buffer_set_byte(buf.buf,buf.writepos,16,(size-10) >> 8);
  buffer_set_byte(buf.buf,buf.writepos,17,(size-10) & 0xff);
  buffer_set_byte(buf.buf,buf.writepos,18,0);
  buffer_set_byte(buf.buf,buf.writepos,19,0);
  ip_build_checksum(buf);
  /* ICMP checksum */
  buffer_set_byte(buf.buf,buf.writepos,34,0x0);
  buffer_set_byte(buf.buf,buf.writepos,35,0x0);
  icmp_checksum += 0x0800;
  icmp_checksum += (icmp_checksum >> 16);
  buffer_set_byte(buf.buf,buf.writepos,36,icmp_checksum >> 8);
  buffer_set_byte(buf.buf,buf.writepos,37,icmp_checksum & 0xff);
  buffer_incpos(buf.writepos,(size>>2)+((size & 3) != 0));
  return;
}

#pragma select handler
static void lltx_handler(chanend ll, struct buffer &buf, unsigned &waiting)
{
  unsigned llval;
  ll :> llval;
  if (llval > 0)
  {
    buf.free += (llval>>2)+((llval & 3) != 0);
    buf.slots_used--;
    assert(buf.free >= 0 && buf.slots_used >= 0);
  }
  if (buf.slots_used > 0)
  {
    unsigned size = buf.sizes[buf.sizepostl].bytes;
    buffer_incsizepos(buf.sizepostl,1);
    ll <: size;
    waiting = 0;
  }
  else
  {
    //printstrln("TX WAITING");
    waiting = 1;
  }
  return;
}

static void make_room(chanend ll, struct buffer &buf, unsigned &waiting, unsigned &hasRoom, unsigned words)
{
  hasRoom = buf.free >= words;
  while(!hasRoom)
  {
    lltx_handler(ll,buf,waiting);
  }
  hasRoom = buf.free >= words;
  assert(hasRoom || buf.slots_used > 0);
  return;
}

#pragma select handler
static void app_tx_server(streaming chanend app, chanend ll, struct buffer &buf, unsigned &waiting, unsigned &hasRoom)
{
  unsigned format, len, words, dst, size;
  startTransactionServer(app,dst,format,len);
  size = 14 + 20 + 8 + (len * format);
  words = (size>>2)+((size & 3) != 0);
  /*printstrln("SIZE: ");
  printintln(size);*/
  make_room(ll,buf,waiting,hasRoom,words);
  buf.slots_used++;
  buf.free -= words;
  buf.sizes[buf.sizeposhd].words = words;
  buf.sizes[buf.sizeposhd].bytes = size;
  buffer_incsizepos(buf.sizeposhd,1);
  for (int i = 0; i < 8; i += 1)
  {
    buf.buf[buffer_offset(buf.writepos,i)] = (arpc.header,unsigned[])[i];
  }
  if (format == 4)
  {
    unsigned word;
    for (int i = 0; i < len; i += 1)
    {
      streamInWord(app,word);
      buf.buf[buffer_offset(buf.writepos,11+i)] = word;
      //printhexln(word);
    }
  }
  else if (format == 1)
  {
    unsigned b;
    for (int i = 0; i < len; i += 1)
    {
      streamInByte(app,b);
    }
  }
  endTransactionServer(app);
  for (int i = 1; i < 8; i += 1)
  {
    buf.buf[buffer_offset(buf.writepos,i)] = (arpc.header,unsigned[])[i];
  }
  buffer_set_byte(buf.buf,buf.writepos,32,arpc.header[32]);
  buffer_set_byte(buf.buf,buf.writepos,33,arpc.header[33]);
  buffer_set_byte(buf.buf,buf.writepos,23,0x11);
  buffer_set_byte(buf.buf,buf.writepos,16,(size - 10) >> 8);
  buffer_set_byte(buf.buf,buf.writepos,17,(size - 10) & 0xff);
  buffer_set_byte(buf.buf,buf.writepos,18,0);
  buffer_set_byte(buf.buf,buf.writepos,19,0);
  ip_build_checksum(buf);
  buffer_set_byte(buf.buf,buf.writepos,34,0x5b);
  buffer_set_byte(buf.buf,buf.writepos,35,0x5b);
  buffer_set_byte(buf.buf,buf.writepos,36,0x5b);
  buffer_set_byte(buf.buf,buf.writepos,37,0x5b);
  buffer_set_byte(buf.buf,buf.writepos,38,(size - 34) >> 8);
  buffer_set_byte(buf.buf,buf.writepos,39,(size - 34) & 0xff);
  buf.buf[buffer_offset(buf.writepos,10)] = 0x7ada0000;
  buffer_incpos(buf.writepos,words);
  if (waiting && size)
  {
    buffer_incsizepos(buf.sizepostl,1);
    ll <: size;
    waiting = 0;
  }
  return;
}

#pragma select handler
static void app_tx_ctrl(chanend ctrl, chanend ll, struct buffer &buf, unsigned &waiting, unsigned &hasRoom)
{
  unsigned words, cval, size;
  ctrl :> cval;
  switch (cval)
  {
    case 1:
      size = 42;
      break;
    case 2:
      ctrl :> size;
      break;
    default:
      size = 0;
      break;
  }
  words = (size>>2)+((size & 3) != 0);
  make_room(ll,buf,waiting,hasRoom,words);
  buf.slots_used++;
  buf.free -= words;
  switch (cval)
  {
    case 1:
      /* ARP response! */
      build_arp_out(buf,ctrl,size);
      break;
    case 2:
      /* ICMP response */
      build_icmp_echo(buf,ctrl,size);
      break;
    default:
      /* Nothing to do! */
      break;
  }
  if (waiting && size)
  {
    buffer_incsizepos(buf.sizepostl,1);
    ll <: size;
    waiting = 0;
  }
  return;
}
      

static void app_tx(struct buffer &buf, streaming chanend app, chanend ll, chanend ctrl)
{
  unsigned hasRoom = buf.free >= BUFFER_MINFREE, waiting = 0;
  while (1)
  {
    #pragma ordered
    select
    {
      case lltx_handler(ll,buf,waiting):
        assert(hasRoom || buf.slots_used > 0);
        break;
      case app_tx_ctrl(ctrl,ll,buf,waiting,hasRoom):
        break;
      case app_tx_server(app,ll,buf,waiting,hasRoom):
        break;
    }
  }
  return;
}

static inline int ip_checksum_valid(struct buffer &buf)
{
  unsigned ip_checksum = 0, i;
  for (i = 14; i < 34; i += 2)
  {
    ip_checksum += buffer_get_byte(buf.buf,buf.readpos,i) | (buffer_get_byte(buf.buf,buf.readpos,i+1) << 8);
  }
  while (ip_checksum >> 16)
  {
    ip_checksum = (ip_checksum & 0xffff) + (ip_checksum >> 16);
  }
  return ((~ip_checksum) & 0xffff) == 0;
}

static inline int is_mac_broadcast(struct buffer &buf)
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

static inline int is_my_ip(struct buffer &buf)
{
  unsigned ip = (buf.buf[buffer_offset(buf.readpos,7)] & 0xffff0000) |
      (buf.buf[buffer_offset(buf.readpos,8)] & 0x0000ffff);
  return ip == (cfg.ip,unsigned);
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
        ctrl <: buffer_get_byte(buf.buf,rp,i);
      }
      ctrl <: buf.buf[buffer_offset(rp,7)];
    }
  }
  return 1;
}

static int handle_icmp_echo(struct buffer &buf, chanend ctrl, unsigned size)
{
  unsigned len;
  if ((buf.buf[buffer_offset(buf.readpos,8)] >> 16) != 0x0008)
  {
    //Invalid type code
    return 0;
  }
  len = byterev(buf.buf[buffer_offset(buf.readpos,4)]) >> 16;
  if (size >= 64 && size != len + 18)
  {
    //Invalid size
    return 0;
  }
  /* Now handle ICMP in TX */
  {
    int i;
    ctrl <: 2;
    ctrl <: size-8;
    master {
      for (i = 38; i < 42; i += 1)
      {
        ctrl <: buffer_get_byte(buf.buf,buf.readpos,i);
      }
      ctrl <: len;
      for (i = 42; i < len - 28 + 42; i += 1)
      {
        ctrl <: buffer_get_byte(buf.buf,buf.readpos,i);
      }
      ctrl <: byterev(buf.buf[buffer_offset(buf.readpos,9)]) >> 16;
    }
  }
  return 1;
}

static int udp_dst_port(struct buffer &buf)
{
  return byterev(buf.buf[buffer_offset(buf.readpos,9)]) >> 16;
}

/*static int udp_src_port(struct buffer &buf)
{
  return byterev(buf.buf[buffer_offset(buf.readpos,8)]) & 0xffff;
}*/

static int udp_len(struct buffer &buf)
{
  return (byterev(buf.buf[buffer_offset(buf.readpos,9)]) & 0xffff)-8;
}

static int handle_udp_tftp(struct buffer &buf, chanend app, unsigned size)
{
  return 0;
}

static inline int ip_fragmented(struct buffer &buf)
{
  return ((buffer_get_byte(buf.buf,buf.readpos,20) >> 5) & 1) || 
    (buffer_get_byte(buf.buf,buf.readpos,20) & 0x1f) ||
    buffer_get_byte(buf.buf,buf.readpos,21);
}

static inline int is_ipv4(struct buffer &buf)
{
  return (buf.buf[buffer_offset(buf.readpos,3)] == 0x00450008);
}

static int handle_udp_5b5b(struct buffer &buf, chanend app, unsigned size)
{
  unsigned dst, len, format;
  if (udp_len(buf) < 10)
  {
    //Malformed prologue
    return 0;
  }
  dst = byterev(buf.buf[buffer_offset(buf.readpos,11)]);
  len = byterev(buf.buf[buffer_offset(buf.readpos,12)]);
  format = len >> 24;
  len &= 0x00ffffff;
  if (len > 0 && len * format + 10 < udp_len(buf))
  {
    //printstrln("ERR NERR");
    //Less data expected than the packet contains!
    return 0;
  }
  startTransactionClient(app,dst,format,len);
  if (len == 0)
  {
    len = udp_len(buf) - 10;
  }
  if (format == 0x1)
  {
    for (int i = 0; i < len; i += 1)
    {
      char b = buffer_get_byte(buf.buf,buf.readpos,52+i);
      streamOutByte(app,b);
    }
  }
  else if (format == 0x4)
  {
    for (int i = 0; i < len; i += 1)
    {
      streamOutWord(app,buf.buf[buffer_offset(buf.readpos,13+i)]);
    }
  }
  endTransactionClient(app);
  return 1;
}

static int handle_udp_lb(struct buffer &buf, chanend app, unsigned size)
{
  unsigned dlen;
  dlen = udp_len(buf) / 4;
  startTransactionClient(app,0x00000102,4,dlen);
  for (int i = 0; i < dlen; i += 1)
  {
    streamOutWord(app,buf.buf[buffer_offset(buf.readpos,11+i)]);
  }
  endTransactionClient(app);
  return 1;
}

static void app_rx(struct buffer &buf, chanend app, chanend ll, chanend ctrl)
{
  int size;
  ll <: 0;
  ll :> size;
  while(1)
  {
    if (size > 60 && (is_mac_broadcast(buf) || is_mac(buf)))
    {
      /* Deal with whatever type of frame we have */
      if (handle_arp(buf,ctrl)); /* No HL interaction, just respond if necessary */
      else if (is_ipv4(buf) && !ip_fragmented(buf) && is_my_ip(buf) && ip_checksum_valid(buf))
      {
        switch (buffer_get_byte(buf.buf,buf.readpos,23))
        {
        case 0x1: //ICMP
          handle_icmp_echo(buf,ctrl,size);
          break;
        case 0x11: //UDP
          if (udp_dst_port(buf) == 69)
          {
            handle_udp_tftp(buf,app,size);
          }
          else if (udp_dst_port(buf) == 0x5b5b)
          {
            handle_udp_5b5b(buf,app,size);
          }
          else if (udp_dst_port(buf) == 0x1b1b)
          {
            handle_udp_lb(buf,app,size);
          }
          break;
        default:
          break;
        }
      }
      /*else if (handle_udp_tftp(buf,app,size));
      else if (handle_udp_5b5b(buf,app,size));*/
    }
    buf.readpos = (buf.readpos + (size>>2) + ((size & 3) != 0)) & (BUFFER_WORDS-1);
    ll <: size;
    ll :> size;
  }
  printstrln("RX EXIT");
  return;
}

void ethernet_app_xc(struct buffer &txbuf, struct buffer &rxbuf, streaming chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl)
{
  chan appctrl;
  par
  {
    app_rx(rxbuf,rxapp,rxctrl,appctrl);
    app_tx(txbuf,txapp,txctrl,appctrl);
  }
  return;
}

#endif
