interface Flooding {

  command void sendMessage(uint8_t * payload);

  command void recieveMessage(pack * msg);

}
//Acknowledgement needed