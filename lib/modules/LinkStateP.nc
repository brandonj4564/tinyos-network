module LinkStateP {
  provides interface LinkState;

  uses interface NeighborDiscovery;

  uses interface Flooding;

  uses interface Boot;

  uses interface Timer<TMilli> as CacheReset;
  uses interface Timer<TMilli> as beaconTimer;

  uses interface Hashmap<uint16_t> as Cache;
  uses interface Hashmap<uint16_t> as RoutingTable;
  uses interface Hashmap<uint32_t *> as NetworkTopo;
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

  uint32_t neighborsArraySizeLimit = 30;

  uint32_t neighborsArray[30]
                         [30]; // change this if neighborsArraySizeLimit changes
  uint16_t neighborsArraySize = 0;

  event void Boot.booted() {
    // start the module
    call CacheReset.startPeriodic(200000);

    call beaconTimer.startOneShot(4060);
  }

  task void computeRoutingTable() {
    // Perform Dijkstra
  }

  event void CacheReset.fired() {
    // reset cache
  }

  event void beaconTimer.fired() {
    if (TOS_NODE_ID == 9) {
      call LinkState.sendLSA();
    }
  }

  event void NeighborDiscovery.listUpdated() {
    dbg(GENERAL_CHANNEL,
        "Neighbor list updated, routing table will be recalculated.\n");

    // Re-send LSA and recompute routing table
    call LinkState.sendLSA();
    post computeRoutingTable();
  }

  command void LinkState.receiveLSA(pack * msg) {
    // recieve neighbor list from other nodes
    // Add neighbor list to networkTopo configuring it to it's sender node
    uint8_t sizeLSA = msg->payload[0];
    uint8_t *payload = (uint8_t *)(msg->payload);
    uint16_t src = msg->src;

    uint16_t i;
    // for (i = 0; i < sizeLSA; i++) {
    //   dbg(GENERAL_CHANNEL, "Contents of Payload: %i\n", payload[i + 1]);
    // }

    if (call NetworkTopo.contains(src)) {
      // src node updated their neighbor list and sent out a new LSA

      uint32_t *neighborList = (uint32_t *)(call NetworkTopo.get(src));
      neighborList[0] = sizeLSA;

      for (i = 1; i < sizeLSA + 1; i++) {
        neighborList[i] = payload[i];
      }

    } else {
      if (neighborsArraySize < neighborsArraySizeLimit) {
        neighborsArray[neighborsArraySize][0] = neighborsListSize;

        for (i = 1; i < sizeLSA + 1; i++) {
          neighborsArray[neighborsArraySize][i] = payload[i];

          call NetworkTopo.insert(msg->src, neighborsArray[neighborsArraySize]);
          neighborsArraySize++;
        }

      } else {
        dbg(GENERAL_CHANNEL,
            "Cannot store node %i's neighbor list! Increase "
            "neighborsArraySizeLimit!\n",
            msg->src);
      }
    }

    post computeRoutingTable();
  }

  command void LinkState.sendLSA() {
    // Having dest = AM_BROADCAST_ADDR means the message never reaches a
    // destination and ends so it floods the network
    uint16_t dest = AM_BROADCAST_ADDR;
    uint16_t TTL = 20;
    uint16_t protocol = PROTOCOL_LSA;
    uint32_t *neighbors = call NeighborDiscovery.getNeighbors();
    uint8_t length = call NeighborDiscovery.getNumNeighbors();

    uint8_t payload[length + 1];
    uint16_t i;

    // The message structure sends the length of the neighbor list as the first
    // element, then the neighbor list right after
    payload[0] = length;
    for (i = 1; i < length + 1; i++) {
      payload[i] = neighbors[i - 1];
    }

    call Flooding.sendMessage(dest, TTL, protocol, payload, length + 1);
  }
}