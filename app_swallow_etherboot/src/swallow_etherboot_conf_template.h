/*
 * swallow_etherboot_conf_template - Configuration file for etherboot
 *
 * COPY ME TO swallow_etherboot_conf.h DO NOT EDIT ME
 *
 * Copyright (C) 2013 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */

/* Config struct */
struct swallow_xlinkboot_cfg swxlb_cfg = {
  2, //boards_w
  3, //boards_h
  1, //do_reset
  SWXLB_POS_BOTTOM, //Boot node position
  {{-1,0,-1,0x00002700,1,5}}, //PLL array
  1, //PLL array size
  XS1_PORT_1D //Rest port: I on old, D on new
};

/* Mac address - XMOS VID, 0x5b (SB), 0xXXXX (unique PID) */
#define SWALLOW_MAC {0x00,0x22,0x97,0x5b,0x00,0x01}



