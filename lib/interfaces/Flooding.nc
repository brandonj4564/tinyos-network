interface Flooding {

  command void start();

  command void sendMessage(uint16_t dest, uint16_t TTL, uint8_t * payload,
                           uint8_t length);

  command void floodMessage(uint16_t TTL, uint16_t protocol, uint8_t * payload,
                            uint8_t length);

  command void receiveMessage(pack * msg);
}
