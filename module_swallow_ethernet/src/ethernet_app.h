/*
 * ethernet_app - "Application layer" thread
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef ETHERNET_APP_H
#define ETHERNET_APP_H

#include <xccompat.h>
#include "ptr.h"
#include "buffer.h"
#ifndef __XC__
  #define streaming
#endif

void ethernet_app(unsigned rxbuf, unsigned txbuf, chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl);
void ethernet_app_xc(struct buffer PTREF txbuf, struct buffer PTREF rxbuf, streaming chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl);


#endif //ETHERNET_APP_H
