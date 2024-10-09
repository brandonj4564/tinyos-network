interface LinkState {
  command void receiveLSA(pack * msg);
  command void sendLSA(pack * msg);
}