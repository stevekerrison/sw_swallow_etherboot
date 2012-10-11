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
#include <ethernet.h>
#include <xtcp.h>

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

/*    PORT_ETH_FAKE, */
  };

out port p_mii_resetn = PORT_ETH_RST_N;
smi_interface_t smi = { 0x1F, PORT_ETH_MDIO, PORT_ETH_MDC };

clock clk_smi = XS1_CLKBLK_5;

xtcp_ipconfig_t ipconfig = {
  { 192, 168, 128, 4 }, // ip address (eg 192,168,0,2)
  { 255, 255, 255, 0 }, // netmask (eg 255,255,255,0)
  { 192, 168, 128, 1 }  // gateway (eg 192,168,0,1)
};

/* XMOS as vendor, UID as "SB (swallow board) and ID number) */
char mac_addr[] = {0x00,0x22,0x97,0x5b,0x00,0x00};

#define TELNET_PORT 23

void tcpEchoRecv(chanend uip, xtcp_connection_t &conn, char data[], int len)
{
  if (len > 0)
  {
    xtcp_init_send(uip,conn);
  }
  return;
}

void tcpEcho(chanend uip)
{
  xtcp_connection_t conn;
  char data[XTCP_CLIENT_BUF_SIZE+1];
  int len;
  xtcp_listen(uip, TELNET_PORT, XTCP_PROTOCOL_TCP);
  while(1)
  {
    select
    {
      case xtcp_event(uip, conn):
        break;
    }
    switch (conn.event) 
    {
    case XTCP_IFUP:
    case XTCP_IFDOWN:
    case XTCP_ALREADY_HANDLED:
      continue;
      break;
    default:
      break;
    }
    if (conn.local_port == TELNET_PORT) {
      switch (conn.event)
        {
        case XTCP_NEW_CONNECTION:
          break;          
        case XTCP_RECV_DATA:
          len = xtcp_recv(uip, data);
          tcpEchoRecv(uip,conn,data,len);
          break;        
        case XTCP_SENT_DATA:
          xtcp_complete_send(uip);
          break;
        case XTCP_REQUEST_DATA:
        case XTCP_RESEND_DATA:
          xtcp_send(uip,data,len);
          break;         
        case XTCP_TIMED_OUT:
        case XTCP_ABORTED:
        case XTCP_CLOSED:
          break;
        default:
          // Ignore anything else
          break;
        }
      conn.event = XTCP_ALREADY_HANDLED;
    }
  }
  return;
}

int main(void) {
	chan rx[1];
	chan tx[1];
	chan xtcp[1];
  
  xscope_register(0);
  xscope_config_io(XSCOPE_IO_BASIC);
  par
  {
    ethernet_server(mii,smi,mac_addr,rx,1,tx,1);
    xtcp_server_uip(rx[0],tx[0],xtcp,1,ipconfig);
    tcpEcho(xtcp[0]);
  }
  return 0;
}
