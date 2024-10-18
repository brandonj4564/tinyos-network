module InternetProtocolP {
  provides interface InternetProtocol;

  uses interface SimpleSend;
  uses interface LinkState;
}

implementation {
  uint16_t sequenceNum = 0;

  void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL,
                uint16_t protocol, uint16_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  command void InternetProtocol.sendMessage(uint16_t dest, uint16_t TTL,
                                            uint8_t * payload, uint8_t length) {
    pack message;
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

    makePack(&message, TOS_NODE_ID, dest, TTL, PROTOCOL_INTERNET, sequenceNum,
             payload, length);
    sequenceNum++;

    call SimpleSend.send(message, nextHop);
  }

  command void InternetProtocol.receiveMessage(pack * msg) {
    // Note: This forwarding module does not check if the nextHop is equal to
    // the node it just received a message from. This means that, theoretically,
    // a loop might be possible
    int nextHop;
    uint16_t dest = msg->dest;
    uint16_t src = msg->src;

    if (dest == TOS_NODE_ID) {
      // Message reached destination
      dbg(GENERAL_CHANNEL, "IP: FINALLY REACHED DESTINATION, SENT FROM %i\n",
          src);
      return;
    }

    // Check TTL and whether or not the current node is the original source
    if (msg->TTL <= 0 || src == TOS_NODE_ID) {
      return;
    }

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
}