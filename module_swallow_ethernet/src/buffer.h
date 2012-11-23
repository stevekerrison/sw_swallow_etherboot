/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef BUFFER_H
#define BUFFER_H

#include "ptr.h"

#ifndef BUFFER_WORDS
#define BUFFER_WORDS 1024 //4K
#endif
#define BUFFER_MINFREE 380
#define BUFFER_SIZES_SIZE (BUFFER_WORDS>>6)

struct buffer_sizes {
  int words;
  int bytes;
};

struct buffer {
  int readpos;
  int writepos;
  int free;
  int slots_used;
  struct buffer_sizes sizes[BUFFER_SIZES_SIZE];
  int sizeposhd;
  int sizepostl;
  unsigned buf[BUFFER_WORDS];
};

void buffer_init(struct buffer PTREF buf);

unsigned buffer_ptr(struct buffer PTREF buf);

#define buffer_offset(pos,inc)  (((pos) + (inc)) & (BUFFER_WORDS-1))
#define buffer_offset_byte(pos,inc) (((pos<<2) + (inc)) & ((BUFFER_WORDS<<2)-1))
#define buffer_get_byte(buf,pos,inc) ((buf,char[])[buffer_offset_byte(pos,inc)])
#define buffer_set_byte(buf,pos,inc,byte) (buf,char[])[buffer_offset_byte(pos,inc)] = byte
#define buffer_incpos(pos,inc)  pos = buffer_offset(pos,inc)
#define buffer_incsizepos(pos,inc) pos = (((pos) + (inc)) & (BUFFER_SIZES_SIZE-1))



#endif //BUFFER_H
