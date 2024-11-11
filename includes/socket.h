#ifndef __SOCKET_H__
#define __SOCKET_H__

enum {
  MAX_NUM_OF_SOCKETS = 10,
  MAX_CONNECTIONS = 10,
  ROOT_SOCKET_ADDR = 255,
  ROOT_SOCKET_PORT = 255,
  SOCKET_BUFFER_SIZE = 128,
};

enum socket_state {
  CLOSED,
  LISTEN,
  ESTABLISHED,
  SYN_SENT,
  SYN_RCVD,
};

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t {
  nx_socket_port_t port;
  nx_uint16_t addr;
}
socket_addr_t;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket.
typedef struct socket_store_t {
  uint8_t flag;
  enum socket_state state;
  bool bound;
  socket_port_t src;
  socket_addr_t dest;

  // This is the sender portion.
  uint8_t sendBuff[SOCKET_BUFFER_SIZE];
  uint8_t lastWritten; // circular buffer, so this is the end index
  uint8_t lastAck;     // this is the start index of the buffer
  uint8_t lastSent;    // this is seq for both client and server

  // This is the receiver portion
  uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
  uint8_t lastRead;     // start index
  uint8_t lastRcvd;     // end index
  uint8_t nextExpected; // this is the client's seq + 1 (ACK)

  uint16_t RTT;
  uint8_t effectiveWindow;
} socket_store_t;

// Created by me :)
typedef struct connection_t {
  // This is the information needed per connection request
  uint8_t srcAddr;
  uint8_t srcPort;
  uint8_t destPort;
  // No need for destAddr, since destAddr always is TOS_NODE_ID
  uint8_t seq;
} connection_t;

#endif
