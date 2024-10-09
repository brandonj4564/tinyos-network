module InternetProtocolP { provides interface InternetProtocol; }

implementation {
  command void InternetProtocol.sendMessage(uint16_t dest, uint16_t TTL,
                                            uint8_t * payload, uint8_t length) {
    // Copied from Flooding

    // pack message;
    // makePack(&message, TOS_NODE_ID, dest, TTL, PROTOCOL_FLOODING,
    // sequenceNum,
    //          payload, length);
    // sequenceNum++;

    // dbg(FLOODING_CHANNEL, "FLOODING: Message sent to %i.\n", dest);
    // call SimpleSend.send(message, AM_BROADCAST_ADDR);
  }
}