// Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H

#include "channels.h"
#include "protocol.h"

enum {
  PACKET_HEADER_LENGTH = 5,
  PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
  MAX_TTL = 15
};

typedef nx_struct pack {
  nx_uint8_t dest;
  nx_uint8_t src;
  nx_uint8_t seq; // Sequence Number
  nx_uint8_t TTL; // Time to Live
  nx_uint8_t protocol;
  nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}
pack;

typedef nx_struct packIP {
  nx_uint8_t src;
  nx_uint8_t dest;
  nx_uint8_t TTL; // Time to Live
  nx_uint8_t protocol;
  nx_uint8_t payload[0];
}
packIP;

typedef nx_struct packTCP {
  nx_uint8_t srcAddr;
  nx_uint8_t srcPort;
  nx_uint8_t destPort;
  nx_uint8_t seq; // initial seq should be randomized based on clock
  nx_uint8_t ack;
  nx_uint8_t flag;
  nx_uint8_t window;
  nx_uint8_t length; // payload size in bytes, needed to keep track of indices
                     // in the buffers
  nx_uint8_t payload[0];
}
packTCP;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input) {
  dbg(GENERAL_CHANNEL,
      "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
      input->src, input->dest, input->seq, input->TTL, input->protocol,
      input->payload);
}

enum { AM_PACK = 6 };

#endif
