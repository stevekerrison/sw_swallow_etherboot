/*
 * swallow_etherboot - Boot a Swallow grid using Ethernet
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#include <platform.h>
#include <print.h>
#include <xscope.h>
#include "smi.h"
#include "mii_driver.h"
#include "mii.h"
#include "pipServer.h"
#include "tcpApplication.h"
#include "ipv4.h"
#include "udpApplication.h"

#define PORT_ETH_FAKE   XS1_PORT_8C
#define PORT_ETH_RXER   XS1_PORT_1H
#define PORT_ETH_RST_N  XS1_PORT_1A

mii_interface_t mii =
  {
    XS1_CLKBLK_1,
    XS1_CLKBLK_2,

    PORT_ETH_RXCLK,
    PORT_ETH_RXER,
    PORT_ETH_RXD,
    PORT_ETH_RXDV,

    PORT_ETH_TXCLK,
    PORT_ETH_TXEN,
    PORT_ETH_TXD,

    PORT_ETH_FAKE,
  };

out port p_mii_resetn = PORT_ETH_RST_N;
smi_interface_t smi = { 0x1F, PORT_ETH_MDIO, PORT_ETH_MDC };

clock clk_smi = XS1_CLKBLK_5;

void udpEcho(streaming chanend ch)
{
  unsigned char buffer [1500];
  unsigned rip, rport;
  int len;
  while (1)
  {
    len = pipApplicationReadUDP(ch, buffer, 0, 1500, rip, rport, 1234);
    pipApplicationWriteUDP(ch, buffer, 0, len, rip, 1234, rport);
  }
}

void tcpEcho(streaming chanend ch)
{
  unsigned char buffer [1500];
  int len;
  pipApplicationAccept(ch, 0);
  while (1)
  {
    len = pipApplicationRead(ch, 0, buffer, 1500);
    pipApplicationWrite(ch, 0, buffer, len);
  }
}

int main(void) {
	streaming chan tcpApps[1];
	streaming chan udpApps[1];
  char ip[] = {4,128,168,192};
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
  pipAssignIPv4((ip,unsigned), 0, 0);
  par
  {
    pipServer(clk_smi, p_mii_resetn, smi, mii, tcpApps, udpApps);
    //udpEcho(udpApps[0]);
    tcpEcho(tcpApps[0]);
  }
  return 0;
}
