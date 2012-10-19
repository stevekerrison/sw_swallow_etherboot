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

struct buffer {
  int readpos;
  int writepos;
  int free;
  int slots_used;
  unsigned buf[BUFFER_WORDS];
};

void buffer_init(struct buffer PTREF buf);

unsigned buffer_ptr(struct buffer PTREF buf);

#define buffer_offset(pos,inc)  ((pos) + (inc)) & (BUFFER_WORDS-1)
#define buffer_incpos(pos,inc)  pos = buffer_offset(pos,inc);



#endif //BUFFER_H
