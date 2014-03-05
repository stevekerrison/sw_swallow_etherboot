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
#include "swallow_tftp_server.h"

#define BUF_SIZE (1600/4)
#define ARP_CACHE_SIZE 1

struct arp_cache_entry {
  unsigned char ip[4];
  unsigned char mac[6];
};

struct arp_cache_entry arp_cache_table[ARP_CACHE_SIZE];

unsigned char ethertype_ip[] = {0x08, 0x00};
unsigned char ethertype_arp[] = {0x08, 0x06};
unsigned char own_mac_addr[6];

static void init_arp_cache()
{
  for (int i = 0; i < ARP_CACHE_SIZE; i += 1)
  {
    (arp_cache_table[i].ip,unsigned[])[0] = 0;
    (arp_cache_table[i].mac,unsigned[])[0] = 0;
    arp_cache_table[i].mac[4] = 0;
    arp_cache_table[i].mac[5] = 0;
  }
}

#pragma unsafe arrays
static int add_arp_cache(unsigned int buf[])
{
  for (int i = 0; i < ARP_CACHE_SIZE; i += 1)
  {
    if ((arp_cache_table[i].ip,unsigned) == 0)
    {
      for (int j = 0; j < 4; j += 1)
      {
        arp_cache_table[i].ip[j] = (buf,unsigned char[])[38+j];
      }
      (arp_cache_table[i].mac,unsigned[])[0] = buf[0];
      arp_cache_table[i].mac[4] = (buf,unsigned char[])[4];
      arp_cache_table[i].mac[5] = (buf,unsigned char[])[5];
      return 1;
    }
  }
  return 0;
}

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

#pragma unsafe arrays
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
  add_arp_cache(txbuf);

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

#pragma unsafe arrays
int is_valid_arp_packet(const unsigned char rxbuf[], int nbytes)
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;

  if (rxbuf[12] != 0x08 || rxbuf[13] != 0x06)
    return 0;

  //printstr("ARP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x01000608)
  {
    //printstr("Invalid et_htype\n");
    return 0;
  }
  if ((rxbuf, const unsigned[])[4] != 0x04060008)
  {
    //printstr("Invalid ptype_hlen\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[5] & 0xFFFF) != 0x0100)
  {
    /* Not a request, so we definitely don't need to reply, but maybe we should cache it! */
    if (((rxbuf, const unsigned[])[5] & 0xFFFF) == 0x0200)
    {
      printstrln("ARP REPLY/ANNOUNCE");
      for (int i = 0; i < ARP_CACHE_SIZE; i += 1)
      {
        if ((arp_cache_table[i].ip,unsigned) == 0)
        {
          for (int j = 0; j < 4; j += 1)
          {
            arp_cache_table[i].ip[j] = rxbuf[28 + j];
            arp_cache_table[i].mac[j] = rxbuf[22 + j];
          }
          arp_cache_table[i].mac[4] = rxbuf[22 + 4];
          arp_cache_table[i].mac[5] = rxbuf[22 + 5];
          printstrln("ARP CACHE UPDATED");
          break;
        }
      }
      /* If the ARP cache is full then we simply ignore the announce/reply */
    }
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[38 + i] != own_ip_addr[i])
    {
      //printstr("Not for us\n");
      return 0;
    }
  }

  return 1;
}

#pragma unsafe arrays
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

#pragma unsafe arrays
int is_valid_icmp_packet(const unsigned char rxbuf[], int nbytes)
{
  static const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;
  unsigned totallen;


  if (rxbuf[23] != 0x01)
    return 0;

  //printstr("ICMP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x00450008)
  {
    //printstr("Invalid et_ver_hdrl_tos\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[8] >> 16) != 0x0008)
  {
    //printstr("Invalid type_code\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[30 + i] != own_ip_addr[i])
    {
      //printstr("Not for us\n");
      return 0;
    }
  }

  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    //printstr("Invalid size\n");
    printintln(nbytes);
    printintln(totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    //printstr("Bad checksum\n");
    return 0;
  }

  return 1;
}

#pragma unsafe arrays
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
    //printstr("Invalid et_ver_hdrl_tos\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[30 + i] != own_ip_addr[i])
    {
      //printstr("Not for us\n");
      return 0;
    }
  }

  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    //printstr("Invalid size\n");
    printintln(nbytes);
    printintln(totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    //printstr("Bad checksum\n");
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
static int handle_udp_5b5b(unsigned char frame[], unsigned frame_size, streaming chanend grid)
{
  unsigned dst, format, len, udp_len;
  if ((frame,unsigned short[])[21] != 0x7ada) //Does UDP payload have "D47A" at the front?
  {
    return 0;
  }
  udp_len = byterev((frame,unsigned short[])[19]) >> 16;
  dst = byterev((frame,unsigned [])[11]);
  /* Support contiguous IDs */
  if ((dst & 0xff) == 0)
  {
    dst = swallow_cvt_chanend((dst | 0x2));
  }
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
  printstrln("START CLIENT");
  printintln(len);
  startTransactionClient(grid,dst,format,len);
  printstrln("CLIENT STARTED");
  if (format == 0x1)
  {
    for (int i = 0; i < len; i += 1)
    {
      grid <: frame[52+i];
    }
  }
  else if (format == 0x4)
  {
    for (int i = 0; i < len; i += 1)
    {
      grid <: byterev((frame,unsigned [])[13+i]);
      printstrln("WORD");
    }
  }
  printstrln("CLOSE");
  endTransactionClient(grid);
  printstrln("DONE");
  return 1;
}

#pragma unsafe arrays
void udp_copy_header(unsigned char rxbuf[], unsigned char txbuf[], unsigned udp_len)
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

#pragma unsafe arrays
unsigned udp_prep_header(unsigned char txbuf[], unsigned payload_len)
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

void handle_debug(unsigned char rxbuf[], unsigned char txbuf[],
  unsigned udp_len, chanend tx, struct swallow_xlinkboot_cfg &cfg) {
  static unsigned short coreidx = 0;
  unsigned ncores = cfg.boards_w * cfg.boards_h * SWXLB_CORES_BOARD, txbytes;
  unsigned maxcores_payload =
    DEBUG_PC_PAYLOAD_LIMIT / sizeof(struct swallow_debug_pc);
  int i;
  udp_copy_header(rxbuf,txbuf,udp_len);
  for (i = 0; coreidx < ncores && i < maxcores_payload;
    i += 1, coreidx += 1) {
    int offset = 42 + (i * sizeof(struct swallow_debug_pc));
    unsigned short sid = swallow_id(coreidx);
    //Logical ID
    txbuf[offset++] = coreidx >> 8;
    txbuf[offset++] = coreidx & 0xff;
    //Node ID
    txbuf[offset++] = sid >> 8;
    txbuf[offset++] = sid & 0xff;
    //JTAG ID
    txbuf[offset++] = 0;
    txbuf[offset++] = 0;
    //Reserved
    txbuf[offset++] = 0;
    txbuf[offset++] = 0;
    //Thread PCs
    for (int t = 0; t < 8; t += 1) {
      unsigned pc;
      read_pswitch_reg(sid,0x40 + t,pc);
      for (int b = 3; b >= 0; b -= 1) {
        txbuf[offset++] = (pc >> (8 * b)) & 0xff;
      }
    }
  }
  if (coreidx >= ncores) {
    //Reset coreidx if we reached end of cores in this debug packet
    coreidx = 0;
  }
  txbytes = udp_prep_header(txbuf,i * sizeof(struct swallow_debug_pc));
  mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
}

static void packet_received(unsigned int rxbuf[BUF_SIZE], unsigned int txbuf[BUF_SIZE],
  unsigned int nbytes, unsigned int src_port, streaming chanend grid_tx, chanend tx,
  struct swallow_xlinkboot_cfg &cfg)
{
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
        swallow_tftp_server((rxbuf,unsigned char[]), (txbuf, unsigned char[]), udp_len, tx, cfg);
        break;
      case 0x1b1b:  //Loopback test
        build_udp_loopback((rxbuf,char[]), (txbuf, unsigned char[]), own_mac_addr, udp_len);
        mac_tx(tx, txbuf, nbytes, ETH_BROADCAST);
        break;
      case 0x5b5b:  //5wallow Board I/O
        handle_udp_5b5b((rxbuf,char[]), nbytes, grid_tx);
        break;
      case 0x5bdb:
        handle_debug((rxbuf,unsigned char[]), (txbuf, unsigned char[]), udp_len, tx, cfg);
        break;
      default:
        //Nothing to do
        break;
    }
  }
  return;
}

#pragma select handler
void grid_printer(streaming chanend grid_print)
{
  static unsigned last_dst = 0;
  unsigned dst, format, length, bidx, i;
  unsigned char buf[IO_REDIRECT_BUF + 1];
  startTransactionServer(grid_print,dst,format,length);
  swallowAssert(format == 1);
  if ((dst & 0xffff0000) != last_dst)
  {
    printstr("\n[");
    printhex(dst);
    printstr("]: ");
    last_dst = dst & 0xffff0000;
  }
  for (i = 0; i < length;)
  {
    for (bidx = 0; bidx < IO_REDIRECT_BUF && i < length; bidx += 1, i += 1)
    {
      grid_print :> buf[i];
    }
    buf[i] = '\0';
    printstr(buf);
  }
  endTransactionServer(grid_print);
  return;
}

#pragma unsafe arrays
#pragma select handler
void grid_outbound(streaming chanend grid_rx, chanend tx, unsigned char txbuf[BUF_SIZE])
{
  unsigned dst, format, length, checksum, ip_len, udp_len, data_len;
  static unsigned short idtf = 1;
  const unsigned char own_ip_addr[4] = OWN_IP_ADDRESS;
  startBurstServer(grid_rx,dst,format,length);
  data_len = format * length;
  udp_len = 18 + data_len;
  ip_len = 20 + udp_len;
  for (int i = 0; i < 6; i += 1)
  {
    txbuf[i + 6] = own_mac_addr[i];
    txbuf[i] = arp_cache_table[0].mac[i];
  }
  for (int i = 0; i < 4; i += 1)
  {
    txbuf[26 + i] = own_ip_addr[i];
    txbuf[30 + i] = arp_cache_table[0].ip[i];
  }
  txbuf[12] = 0x08;
  txbuf[13] = 0x00;
  txbuf[14] = 0x45;
  txbuf[15] = 0x00;
  txbuf[16] = ip_len >> 8;
  txbuf[17] = ip_len & 0xff;
  txbuf[18] = idtf >> 8;
  txbuf[19] = (idtf++) & 0xff;
  txbuf[20] = 0x40;
  txbuf[21] = 0x00;
  txbuf[22] = 0x40;
  txbuf[23] = 0x11;
  txbuf[24] = 0x00;
  txbuf[25] = 0x00;
  checksum = checksum_ip(txbuf);
  txbuf[24] = checksum >> 8;
  txbuf[25] = checksum & 0xff; 
  txbuf[34] = 0x5b;
  txbuf[35] = 0x5b;
  txbuf[36] = 0x5b;
  txbuf[37] = 0x5b;
  txbuf[38] = udp_len >> 8;
  txbuf[39] = udp_len & 0xff;
  txbuf[40] = 0x00;
  txbuf[41] = 0x00;
  txbuf[42] = 0xda;
  txbuf[43] = 0x7a;
  (txbuf,unsigned[])[11] = byterev(dst);
  (txbuf,unsigned[])[12] = byterev((format << 24) | (length & 0x00ffffff));
  if (format == 4)
  {
    for (int i = 0; i < length; i += 1)
    {
      grid_rx :> (txbuf,unsigned[])[13 + i];
      (txbuf,unsigned[])[13 + i] = byterev((txbuf,unsigned[])[13 + i]);
    }
  }
  else
  {
    for (int i = 0; i < length; i += 1)
    {
      grid_rx :> txbuf[52 + i];
    }
  }
  endBurstServer(grid_rx);
  for (int i = ip_len + 14; i < 60; i += 1)
  {
    txbuf[i] = 0x0;
  }
  //Throw away if we don't have anywhere to send it
  if ((arp_cache_table[0].ip,unsigned) != 0)
  {
    //printstrln("TXing");
    mac_tx(tx, (txbuf,unsigned[]), (60 > (ip_len + 14)) ? 60 : (ip_len + 14), ETH_BROADCAST);
  }
  return;
}


void swallow_ethernet(chanend tx, chanend rx, streaming chanend grid_tx, streaming chanend grid_rx,
  streaming chanend grid_print, struct swallow_xlinkboot_cfg &cfg)
{
  unsigned int rxbuf[BUF_SIZE];
  unsigned int txbuf[BUF_SIZE];
  unsigned tmp;
  
  swallow_xlinkboot_xscope_init();
  swallow_tftp_init_cfgstr(cfg);
  sw_nrows = cfg.boards_h * SWXLB_CHIPS_H;
  sw_ncols = cfg.boards_w * SWXLB_CHIPS_W * SWXLB_CORES_CHIP;
  
  init_arp_cache();
  
  //::get-macaddr
  mac_get_macaddr(tx, own_mac_addr);
  //::
  printstr("RX: ");
  printhexln(getLocalStreamingChanendId(grid_rx));
  printstr("PRINT: ");
  printhexln(getLocalStreamingChanendId(grid_print));
  //::setup-filter
#ifdef CONFIG_FULL
  mac_set_custom_filter(rx, 0x1);
#endif
  //::
  //printstr("Test started\n");
  /*read_sswitch_reg(SWXLB_BOOT_ID,0xd,tmp);
  printhexln(tmp);
  read_sswitch_reg(SWXLB_BOOT_ID,0xc,tmp);
  printhexln(tmp);*/
  //::mainloop
  while (1)
  {
    unsigned int src_port;
    unsigned int nbytes, dst, format, length;
    select
    {
      case mac_rx(rx, (rxbuf,char[]), nbytes, src_port):
        packet_received(rxbuf, txbuf, nbytes, src_port, grid_tx, tx, cfg);
        break;
      case grid_outbound(grid_rx, tx, (txbuf,unsigned char[])):
        break;
      case grid_printer(grid_print):
        break;
    }
  }
}

