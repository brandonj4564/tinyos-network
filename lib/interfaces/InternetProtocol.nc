interface InternetProtocol {
  /*
  Simpler module compared to Link State. Only needs to consult the routing table
  from LS and forward and receive packets.
  */

  command void sendMessage(uint16_t dest, uint16_t TTL, uint16_t protocol,
                           uint8_t * payload, uint8_t length);

  command void receiveMessage(pack * msg);
}