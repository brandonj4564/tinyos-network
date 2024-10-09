module LinkState {
  provides interface LinkState;

  uses interface NeighborDiscovery;

  uses interface Boot;

  uses interface Timer<TMilli> as cacheReset;

  uses interface Hashmap<uint16_t> as cache;
  uses interface Hashmap<uint16_t> as routingTable;
  uses interface Hashmap<uint16_t> as networkTopo;

  
}

implementation {
  /*
  The link state routing module needs to send a node's neighbor list to the
  entire network. This means we need a new Flooding command to flood the
  entire network, not just to one node. Also means we need a new
  PROTOCOL_LINK_STATE for packets. We need a cache that tracks sequence
  number.

  Need some data structure, probably a 2d array alongside a hashmap similar to
  NeighborDiscovery, to store a node's neighbors and cost to reach said
  neighbor.

  We need to implement Dijkstra's algorithm, probably in the form of a task.
  Before performing Dijkstra, we need to wait until the node has a good enough
  understanding of the network in total. We can do this with a timer.

  Rerun Dijkstra after any change to the network topography occurs. The output
  from Dijkstra should be stored in the routing table.

  The routing table should probably be a hashmap that stores a pointer to an
  array again. The key is the final destination node, and the array stores the
  next hop, the cost, a backup next hop, and the backup cost. This routing
  table needs to be accessed by InternetProtocol.
  */

  event void Boot.booted() {
    // start the module
  }

  event void NeighborDiscovery.listUpdated() {
    dbg(GENERAL_CHANNEL, "Routing Table will be recalculated\n");
    computeRoutingTable();
  }

  command void LinkState.receiveLSA(pack * msg){
    //recieve neighbor list from other nodes
    //Add neighbor list to networkTopo configuring it to it's sender node
     

  }

  command void LinkState.sendLSA(pack * msg){
    
  } 

  task void computeRoutingTable(){
    //Preform Dijkstra

  }

}