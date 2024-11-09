module InternetProtocolP {
  provides interface InternetProtocol;

  uses interface SimpleSend;
  uses interface LinkState;
  uses interface Transport;
}

implementation {
  // LSA pack struct
  // Only made this because the high level design slides said to
  typedef nx_struct packIP {
    nx_uint8_t src;
    nx_uint8_t dest;
    nx_uint8_t TTL; // Time to Live
    nx_uint8_t protocol;
    nx_uint8_t payload[0];
  }
  packIP;

  uint16_t sequenceNum = 0;

  void makePack(pack * Package, uint8_t src, uint8_t dest, uint8_t TTL,
                uint8_t protocol, uint8_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  void makeIP(packIP * Package, uint16_t src, uint16_t dest, uint8_t TTL,
              uint8_t protocol, uint8_t * payload, uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  command void InternetProtocol.sendMessage(uint16_t dest, uint8_t TTL,
                                            uint16_t protocol,
                                            uint8_t * payload, uint8_t length) {
    pack message;
    // Putting the payload in packIP reduces the available space by 6 bytes,
    // leaving only 14 bytes.
    // 6 entire bytes of overhead!!!
    packIP datagramIP;
    uint8_t sizeIP = sizeof(packIP) + length;
    uint8_t normalPayload[PACKET_MAX_PAYLOAD_SIZE];

    // Second argument is a boolean for backup hop
    int nextHop = call LinkState.getNextHop(dest, 0);

    if (nextHop < 0) {
      // nextHop invalid
      nextHop = call LinkState.getNextHop(dest, 1);
    }

    if (nextHop < 0) {
      // even backupHop is invalid
      dbg(GENERAL_CHANNEL, "No valid route to %i in routing table.\n", dest);
      return;
    }

    makeIP(&datagramIP, TOS_NODE_ID, dest, TTL, protocol, payload, length);
    memcpy(normalPayload, (void *)(&datagramIP), sizeIP);

    makePack(&message, TOS_NODE_ID, dest, TTL, PROTOCOL_IP, sequenceNum,
             normalPayload, sizeIP);
    sequenceNum++;

    dbg(GENERAL_CHANNEL, "IP: Forwarding message to %i.\n", nextHop);
    call SimpleSend.send(message, nextHop);
  }

  command void InternetProtocol.receiveMessage(pack * msg) {
    // Note: This forwarding module does not check if the nextHop is equal to
    // the node it just received a message from. This means that, theoretically,
    // a loop might be possible
    int nextHop;
    packIP *datagram = (packIP *)msg->payload;

    uint16_t dest = datagram->dest;
    uint16_t src = datagram->src;

    if (dest == TOS_NODE_ID) {
      // Message reached destination
      dbg(GENERAL_CHANNEL, "IP: FINALLY REACHED DESTINATION, SENT FROM %i\n",
          src);

      // Send a ping reply
      if (datagram->protocol == PROTOCOL_PING) {
        char *payload = "Ping Reply received.";

        dbg(GENERAL_CHANNEL, "Payload: %s\n", (char *)datagram->payload);

        call InternetProtocol.sendMessage(src, 10, PROTOCOL_PINGREPLY,
                                          (uint8_t *)payload, 20);

      } else if (datagram->protocol == PROTOCOL_PINGREPLY) {
        dbg(GENERAL_CHANNEL, "Payload: %s\n", (char *)datagram->payload);

      } else if (datagram->protocol == PROTOCOL_TCP) {
        // TCP packet, pass to Transport
        call Transport.receive((uint8_t *)datagram->payload);
      }
      return;
    }

    // Check TTL and whether or not the current node is the original source
    if (datagram->TTL <= 0 || src == TOS_NODE_ID) {
      return;
    }

    datagram->TTL = datagram->TTL - 1;

    nextHop = call LinkState.getNextHop(dest, 0);
    if (nextHop < 0) {
      // nextHop invalid
      nextHop = call LinkState.getNextHop(dest, 1);
    }

    if (nextHop < 0) {
      // even backupHop is invalid
      dbg(GENERAL_CHANNEL, "No valid route to %i in routing table.\n", dest);
      return;
    }

    dbg(GENERAL_CHANNEL, "IP: Forwarding message to %i.\n", nextHop);
    call SimpleSend.send(*msg, nextHop);
  }

  event void Transport.newConnectionReceived() {}
}