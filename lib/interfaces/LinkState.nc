interface LinkState {
  command void receiveLSA(pack * msg);
  command void sendLSA();

  // If backup is true, return backup value
  command int getNextHop(int dest, bool backup);
  command int getCost(int dest, bool backup);

  // Gets the ids of all nodes with an active route in the routing table
  command void getActiveRoutes(int *routes);
  command int getNumActiveRoutes();

  // called by TestSim.py
  command void printAllLSA();
}