/*
 * swallow_ethernet - Toplevel ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#include "buffer.h"

void buffer_init(struct buffer *buf)
{
  buf->readpos = 0;
  buf->writepos = 0;
  buf->slots_used = 0;
  buf->sizeposhd = 0;
  buf->sizepostl = 0;
  buf->free = BUFFER_WORDS;
}

unsigned buffer_ptr(struct buffer *buf)
{
  return (unsigned)buf;
}

