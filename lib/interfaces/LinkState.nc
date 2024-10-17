interface LinkState {
  command void receiveLSA(pack * msg);
  command void sendLSA();

  // If backup is true, return backup hop
  command int getNextHop(int dest, bool backup);
}