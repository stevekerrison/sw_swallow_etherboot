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
    //printstr("Not a request\n");
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
  //printstr("Test started\n");

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
