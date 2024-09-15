interface NeighborDiscovery {
  command void start();

  // beaconSentReceived is what happens when a node receives a BEACON SEND
  // the node sends a BEACON RESPONSE
  command void beaconSentReceived(pack * msg);

  // beaconResponseReceived is when the node receives a BEACON RESPONSE
  // the node will add the address in the beacon response to the neighbor list
  command void beaconResponseReceived(pack * msg);
}