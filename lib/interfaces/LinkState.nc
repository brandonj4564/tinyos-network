interface LinkState {
  command void receiveLSA(pack * msg);
  command void sendLSA();
  command int getNextHop(int dest);
}