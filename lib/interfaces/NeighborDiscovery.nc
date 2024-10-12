interface NeighborDiscovery {

  // beaconSentReceived is what happens when a node receives a BEACON SEND
  // the node sends a BEACON RESPONSE
  command void beaconSentReceived(pack * msg);

  // beaconResponseReceived is when the node receives a BEACON RESPONSE
  // the node will add the address in the beacon response to the neighbor list
  command void beaconResponseReceived(pack * msg);

  // return array of list of neighbors
  command uint32_t *getNeighbors();

  // return array of connection strengths
  command float getNeighborLinkQuality(uint32_t neighbor);


  // returns number of neightbors
  command uint16_t getNumNeighbors();
  
  event void listUpdated();
}