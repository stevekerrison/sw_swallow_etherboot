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

#define SENDING   0x4
#define RECEIVING 0x8
#define WAITING   0x2
#define IDLE      0x1

#define READY     0x1
#define BOOTING   0x2
#define END       0x4
#define GETSIZE   0x8
#define GETOFFSET 0x10

#define RRQ       1
#define WRQ       2
#define DATA      3
#define ACK       4
#define ERROR     5

//#define DEBUG
#ifdef DEBUG
  #undef DBG
  #define DBG(x) x;
#else
  #undef DBG
  #define DBG(x)
#endif

unsigned char cfg_str[8];

unsigned state = READY, cores, block = 0, word, node = 0, ce = 0,
  crc = 0xd15ab1e, imsize, impos, bufpos = 46, bytepos, corecount, gridcores;

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
  gridcores = cfg.boards_w * cfg.boards_h * SWXLB_CORES_BOARD;
  return;
}

static int getword(unsigned char rxbuf[], unsigned udp_len, unsigned &bufpos, unsigned &bytepos, unsigned &word)
{
  while(bufpos < udp_len + 34)
  {
    word <<= 8;
    word |= rxbuf[bufpos++];
    bytepos += 1;
    if (bytepos >= 4)
    {
      bytepos = 0;
      word = byterev(word);
      return 1;
    }
  }
  //printstrln("Time for a new packet");
  //printintln(bufpos);
  bufpos = 46;
  return 0;
}

static void swallow_tftp_reset()
{
  state = READY;
  bufpos = 46;
  bytepos = 0;
  block = 0;
  node = 0;
  corecount = 0;
}

/* Send all the cores dimension data and put the grid into action! */
static void swallow_init_sync(void)
{
  /* "Column-major" node iteration so that cores start running in a way
   * that's sympathetic to the dimension-order routing, which starts
   * verically. */
  DBG(printstrln("SYNC"));
  for (int c = 0; c < sw_ncols; c += 1)
  {
    for (int r = 0; r < sw_nrows; r += 1)
    {
      asm("setd res[%0],%1"::"r"(ce),"r"((swallow_lookup(r,c) << 16) | 0x0002));
      asm("out res[%1],%0"::"r"(sw_nrows),"r"(ce));
      asm("out res[%1],%0"::"r"(sw_ncols),"r"(ce));
      asm("outct res[%0],2"::"r"(ce)); /* Pause, because we'll send the CT_END lter */
    }
  }
  for (int c = 0; c < sw_ncols; c += 1)
  {
    for (int r = 0; r < sw_nrows; r += 1)
    {
      asm("setd res[%0],%1"::"r"(ce),"r"((swallow_lookup(r,c) << 16) | 0x0002));
      asm("outct res[%0],1"::"r"(ce));
    }
  }
  DBG(printstrln("SYNC'd"));
  return;
}

static int tftp_booting(unsigned char rxbuf[], unsigned udp_len)
{
  while(impos < imsize)
  {
    if (!getword(rxbuf,udp_len,bufpos,bytepos,word))
    {
      //DBG(printintln(bufpos));
      return 0;
    }
    streamOutWord(ce,word);
    impos++;
  }
  if (impos == imsize) //End of image
  {
    streamOutWord(ce,crc);
    asm("outct res[%0],1\n"
      "chkct res[%0],1\n"::"r"(ce));
    state = GETOFFSET;
    node++;
    DBG(printstrln("Done!"));
  }
  return state != END;
}

/* Send an idle image to all unused nodes */
static void swallow_idle_core()
{
  for (; node != word; node += 1)
  {
    unsigned size, loc, w;
    DBG(printstr("Idle: ");\
    printintln(node);\
    printchar(' ');\
    printhexln(swallow_id(node)););
    asm("ldap r11,idleprog\n"
      "mov %0,r11\n"
      "ldap r11,idleprog_end\n"
      "sub %0,r11,%0\n"
      "shr %0,%0,2":"=r"(size):);
    asm("setd res[%0],%1"::"r"(ce),"r"((swallow_id(node) << 16) | 0x2));
    asm("ldap r11,idleprog\n"
      "mov %0,r11":"=r"(loc)::"r11");
    asm("out res[%0],%0\n"
      "out res[%0],%1"::"r"(ce),"r"(size));
    for (int i = loc; i < loc + (size*4); i += 4)
    {
      asm("ldw %0,%1[0]\n"
        "out res[%2],%0\n":"=r"(w):"r"(i),"r"(ce));
    }
    asm("out res[%0],%1\n"::"r"(ce),"r"(crc));
    asm("outct res[%0],1\n"
      "chkct res[%0],1\n"::"r"(ce));
  }
  return;
}

static int tftp_getoffset(unsigned char rxbuf[], unsigned udp_len)
{
  if (getword(rxbuf,udp_len,bufpos,bytepos,word))
  {
    if (word == 0xffffffff)
    {
      state = END;
      return 0;
    }
    if (word >= gridcores)
    {
      DBG(printstrln("BAD CORE OFFSET"));
      swallow_tftp_reset();
      return -3;
    }
    swallow_idle_core();
    state = GETSIZE;
    return 1;
  }
  return 0;
}

static int tftp_getsize(unsigned char rxbuf[], unsigned udp_len)
{
  if (getword(rxbuf,udp_len,bufpos,bytepos,word))
  {
    imsize = word;
    impos = 0;
    asm("setd res[%0],%1"::"r"(ce),"r"((swallow_id(node) << 16) | 0x2));
    DBG(printstr("["));
    DBG(printhex((swallow_id(node) << 16) | 0x2));
    DBG(printstr("]"));
    streamOutWord(ce,ce);
    streamOutWord(ce,imsize);
    state = BOOTING;
    return 1;
  }
  return 0;
}

//Steve's hideous state machine (doubt it'll catch on like Duff's device)
static int swallow_tftp_boot(unsigned char rxbuf[], unsigned udp_len, struct swallow_xlinkboot_cfg &cfg)
{
  int result = 1;
  if (bufpos == 46)
  {
    unsigned newblock = (rxbuf[44] << 8) | rxbuf[45];
    unsigned opcode = (rxbuf[42] << 8) | rxbuf[43];
    if (opcode != DATA || newblock != block + 1)
    {
      DBG(printstrln("BAD BLOCK OR OPCODE"));
      DBG(printhexln(opcode));
      DBG(printhexln(newblock));
      DBG(printhexln(block));
      swallow_tftp_reset();
      return -4;
    }
    block += 1;
  }
  if (state == READY)
  {
    //Check for 0x5b magic number and version 0 of SGB format
    if (rxbuf[46] != 0x5b || rxbuf[47] != 0)
    {
      DBG(printstrln("BAD HEADER"));
      swallow_tftp_reset();
      return -4;
    }
    cores = ((rxbuf[50] << 8) | rxbuf[49]);
    if (cores > cfg.boards_w * cfg.boards_h * SWXLB_CORES_BOARD)
    {
      DBG(printstrln("NOT ENOUGH CORES AVAILABLE"));
      swallow_tftp_reset();
      return -3;
    }
    //TODO: Implement rxbuf[51] (PLL) check and implementation...
    if (rxbuf[48] == 1)
    {
      DBG(printstr("Reset... "));
      swallow_xlinkboot(cfg.boards_w,cfg.boards_h,1,cfg.position,cfg.PLL,cfg.PLL_len,cfg.reset_port);
      DBG(printstrln("Done!"));
    }
    node = 0;
    state = GETOFFSET;
    word = 0;
    imsize = 0;
    impos = 0;
    bufpos = 52;
    bytepos = 0;
  }
  while(result > 0)
  {
    if (state == GETOFFSET)
    {
      result = tftp_getoffset(rxbuf,udp_len);
      if (result < 0)
        return result;
      DBG(printint(node));
      DBG(printstr("("));
    }
    //Intentional lack of else!
    if (state == GETSIZE)
    {
      result = tftp_getsize(rxbuf,udp_len);
      if (result < 0)
        return result;
      DBG(printhex(imsize));
      DBG(printstr(")"));
    }
    //Intentional lack of else!
    if (state == BOOTING)
    {
      result = tftp_booting(rxbuf,udp_len);
      if (result < 0)
        return result;
    }
  }
  //Intentional lack of else!
  if (state == END)
  {
    if (udp_len < 512 + 4 + 8) //If this is the last frame, do some final checks
    {
      if (bufpos + 1 < udp_len + 34)
      {
        DBG(printstrln("TOO MUCH DATA"));
        //We didn't read all the data? Something fishy is going on!
        swallow_tftp_reset();
        return -4;
      }
      else
      {
      unsigned oldblock = block;
      word = cfg.boards_w * cfg.boards_h * SWXLB_CORES_BOARD;
      //node += 1;
      swallow_idle_core();
      swallow_tftp_reset();
      swallow_init_sync();
      return oldblock;
      }
    }
  }
  return block;
}

void swallow_tftp_server(unsigned char rxbuf[], unsigned char txbuf[], unsigned udp_len, chanend tx,
  struct swallow_xlinkboot_cfg &cfg)
{
  int boot_result;
  static unsigned state = IDLE;
  unsigned opcode = (rxbuf[42] << 8) | rxbuf[43];
  unsigned txbytes;
  udp_copy_header(rxbuf,txbuf, udp_len);
  if (!ce)
  {
    ce = getChanend(0x2); //Get chanend to somewhere useless
  }
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
      txbuf[46+i++] = '\n';
      txbuf[46+i] = '\0';
      txbytes = udp_prep_header(txbuf,i+4);
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
      txbytes = udp_prep_header(txbuf,4);
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
    if ((boot_result = swallow_tftp_boot(rxbuf, udp_len, cfg)) >= 0)
    {
      txbuf[42] = 0;
      txbuf[43] = ACK;
      txbuf[44] = boot_result >> 8;
      txbuf[45] = boot_result & 0xff;
      //If the data packet isn't full, then we're done!
      if (udp_len < 512 + 4 + 8)
      {
        state = IDLE;
      }
      txbytes = udp_prep_header(txbuf,4);
    }
    else
    {
      txbuf[42] = 0;
      txbuf[43] = ERROR;
      txbuf[44] = 0;
      txbuf[45] = -boot_result;
      txbuf[46] = '\0';
      txbytes = udp_prep_header(txbuf,5);
    }
    mac_tx(tx, (txbuf,unsigned []), txbytes, ETH_BROADCAST);
  }
  return;
}
