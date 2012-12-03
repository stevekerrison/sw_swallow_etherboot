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

static void app_tx(struct buffer &buf, streaming chanend app, chanend ll, chanend ctrl)
{
  unsigned cval, r = getLocalChanendId(ll);
  unsigned hasRoom = buf.free >= BUFFER_MINFREE, waiting = 0, llval, size;
  asm("mov %0,%1":"=r"(cval):"r"(app));
  while (1)
  {
    #pragma ordered
    select
    {
      case ll :> llval:
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
        assert(hasRoom || buf.slots_used > 0);
        break;
      case ctrl :> cval:
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
        hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
        while (!hasRoom)
        {
          printstrln("TX FULL");
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
          hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
          assert(hasRoom || buf.slots_used > 0);
        }
        buf.slots_used++;
        buf.free -= (size>>2)+((size & 3) != 0);
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
        }
        break;
      case app :> cval:
      {
        unsigned format, len;
        startTransactionServer(app,cval,format,len);
        size = 14 + 20 + 8 + (len * format);
        /* printstrln("SIZE: ");
        printintln(size); */
        hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
        while (!hasRoom)
        {
          printstrln("TX FULL");
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
          hasRoom = buf.free >= (size>>2)+((size & 3) != 0);
          assert(hasRoom || buf.slots_used > 0);
        }
        buf.slots_used++;
        buf.free -= (size>>2)+((size & 3) != 0);
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
        buffer_incpos(buf.writepos,(size>>2)+((size & 3) != 0));
        if (waiting && size)
        {
          buffer_incsizepos(buf.sizepostl,1);
          ll <: size;
        }
        break;
      }
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
  if (buf.buf[buffer_offset(buf.readpos,3)] != 0x00450008)
  {
    //Invalid et_ver_hdrl_tos
    return 0;
  }
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

static int udp_src_port(struct buffer &buf)
{
  return byterev(buf.buf[buffer_offset(buf.readpos,8)]) & 0xffff;
}

static int udp_len(struct buffer &buf)
{
  return (byterev(buf.buf[buffer_offset(buf.readpos,9)]) & 0xffff)-8;
}

static int handle_udp_tftp(struct buffer &buf, chanend app, unsigned size)
{
  return 0;
}

static int handle_udp_5b5b(struct buffer &buf, chanend app, unsigned size)
{
  unsigned dst, rtn, len, format, rtflag, proto, fmtp;
  return 0;
  if (udp_len(buf) < 10)
  {
    //Malformed prologue
    return 0;
  }
  dst = byterev(buf.buf[buffer_offset(buf.readpos,11)]);
  len = byterev(buf.buf[buffer_offset(buf.readpos,12)]);
  format = len >> 24;
  len &= 0x00ffffff;
  /*printstr("Destination: ");
  printhexln(dst);
  printstr("Format: ");
  printhexln(format);
  printstr("Length: ");
  printintln(len);
  printintln(udp_len(buf));*/
  if (len * format + 10 < udp_len(buf))
  {
    printstrln("ERR NERR");
    //Less data expected than the packet contains!
    return 0;
  }
  startTransactionClient(app,dst,format,len);
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
      else if (is_my_ip(buf) && ip_checksum_valid(buf))
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


