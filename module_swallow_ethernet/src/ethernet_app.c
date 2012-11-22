/*
 * ethernet_app - "Application layer" thread
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#include <xccompat.h>
#include "ethernet_app.h"
#include "ptr.h"
#include "buffer.h"

/* Flaunt parallel usage rules */
void ethernet_app(unsigned txbuf, unsigned rxbuf, chanend txapp, chanend rxapp, chanend txctrl, chanend rxctrl)
{
  return ethernet_app_xc((struct buffer *)txbuf,(struct buffer *)rxbuf,txapp,rxapp,txctrl,rxctrl);
}

