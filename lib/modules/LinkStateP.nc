module LinkStateP {
  provides interface LinkState;

  uses interface NeighborDiscovery;

  uses interface Flooding;

  uses interface Boot;

  uses interface Timer<TMilli> as CacheReset;
  uses interface Timer<TMilli> as beaconTimer;

  uses interface Hashmap<uint16_t> as Cache;
  uses interface Hashmap<uint32_t *> as RoutingTable;
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

  uint32_t routingArraySizeLimit = 5;
  uint32_t routingArray[30][5]; // change second part if routingArraySizeLimit
                                // changes
  // Routing Array Structure:
  // [valid?, next hop, cost, backup next hop, backup cost]
  // [1, 2, 0.8, 5, 0.9]

  event void Boot.booted() {
    // start the module
    call CacheReset.startPeriodic(200000);

    call beaconTimer.startOneShot(10000);
  }

  uint32_t calcLinkToCost(int link) {
    // Link is the link quality, a value between 0 and 1
    // Realistically, because there is a threshold, the link quality is a
    // value between 50 and 100 (percent)

    return (100 + 350 * ((100 - (float)link) / 100));
    // In practice, this calc returns about 110 at lowest and 275 at highest
    // So a perfect connection link is about 110 cost
  }

  task void computeRoutingTable() {
    // Perform Dijkstra
    // What we need ----------------------
    // 1. We need all nodes considered array, use a list??
    //    The initial node would be the node we are in
    // 2. for each node in the list make the cost infinity or equal to immediate
    // 3. While loop going forever
    // 4. make unconsidered list equal to all nodes except the current node
    // 5. Then go to the next lowest node.
    // 6. add it to cosidered, remove from unconsidered.
    // 7. Look at all neighbors in that node and add those costs to the cost
    // table
    // 8. repeat 5 to 7 while also checking if its shorter than the original
    // cost

    // Placeholder infinity for Dijkstra
    uint32_t maxCost = 10000;

    uint32_t cost[neighborsArraySizeLimit];
    uint32_t secondBestCost[neighborsArraySizeLimit];
    uint32_t nextHop[neighborsArraySizeLimit];
    uint32_t nodes[neighborsArraySizeLimit];
    uint32_t unconsidered[neighborsArraySizeLimit];
    // Step 2
    uint32_t *immNeighbors =
        (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint32_t numNeighbors = call NeighborDiscovery.getNumNeighbors();

    uint32_t i;

    // Initializing the cost array, start with all nodes being "infinity"
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (neighborsArray[i][0] == 1) {
        cost[i] = maxCost;
        secondBestCost[i] = maxCost;
        // Creates copy so we can remove later
        unconsidered[i] = 1;
      } else {
        unconsidered[i] = 0;
      }
    }
    cost[TOS_NODE_ID] = 0;
    secondBestCost[TOS_NODE_ID] = 0;

    // This node's immediate neighbors have their cost overwritten
    for (i = 0; i < numNeighbors; i++) {
      uint32_t n = immNeighbors[i];
      uint32_t startingCost = calcLinkToCost(
          call NeighborDiscovery.getNeighborLinkQuality(n) * 100);
      // dbg(GENERAL_CHANNEL, "cost: %i\n", startingCost);
      cost[n] = startingCost;
      secondBestCost[n] = startingCost;
      unconsidered[n] = 1;
      nextHop[i] = i;
    }

    while (1) {
      uint32_t emptyCheck = 0;
      uint32_t lowValue = maxCost; // low cost comparison
      uint32_t currentLow;         // lowest cost node id
      uint32_t j;
      uint32_t neighLength;

      // checks if unconsidered list is empty
      for (i = 0; i < neighborsArraySizeLimit; i++) {
        emptyCheck += unconsidered[i];
      }
      if (emptyCheck == 0) {
        break;
      }

      for (i = 0; i < neighborsArraySizeLimit; i++) {
        if (unconsidered[i] == 1 &&
            cost[i] <= lowValue) { // check very carefully later
          currentLow = i;
          lowValue = cost[i];
        }
      }

      unconsidered[currentLow] = 0;
      // current low is equal to next node
      // get the neighbors of that node and add it to cost in table.

      neighLength = neighborsArray[currentLow][1];
      for (j = 1; j < neighLength + 1; j++) {
        // Remember: Structure of the neighborsArray
        // [active?, numNeighbors, neighbor1, LQ1, neighbor2, LQ2...]
        // [1, 2, 5, 75, 7, 20]
        uint32_t currentNode = neighborsArray[currentLow][j * 2];
        // adds cost of current low node to the ones of the neighbor nodes
        // to get the cost from currentNode(TOS_NOde...).
        float tempCost =
            cost[currentNode] + neighborsArray[currentLow][j * 2 + 1];
        if (tempCost < cost[currentNode]) {
          cost[currentNode] = tempCost;
          // store the next hop from currentNode, working backwords
          nextHop[currentNode] = currentLow;
        } else if (tempCost < secondBestCost[currentNode]) {
          secondBestCost[currentNode] = tempCost;
        }
      }
    }
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
    if (TOS_NODE_ID == 9) {
      call LinkState.sendLSA();
    }
    post computeRoutingTable();
  }

  command void LinkState.receiveLSA(pack * msg) {
    // recieve neighbor list from other nodes
    // Add neighbor list to networkTopo configuring it to it's sender node
    uint16_t sizeLSA = msg->payload[0] * 2 + 1;
    uint8_t *payload = (uint8_t *)(msg->payload);
    uint16_t src = msg->src;

    uint16_t i;
    dbg(GENERAL_CHANNEL, "LSA from %i\n", src);
    for (i = 0; i < sizeLSA; i++) {
      dbg(GENERAL_CHANNEL, "Contents of Payload: %i\n", payload[i]);
    }

    if (src >= neighborsArraySizeLimit) {
      dbg(GENERAL_CHANNEL,
          "Cannot store node %i's neighbor list! Increase "
          "neighborsArraySizeLimit!\n",
          msg->src);
      return;
    }

    neighborsArray[src][0] = 1; // This node's neighbors are tracked
    for (i = 0; i < sizeLSA; i++) {
      neighborsArray[src][i + 1] = payload[i];
    }

    post computeRoutingTable();
  }

  command void LinkState.sendLSA() {
    // Having dest = AM_BROADCAST_ADDR means the message never reaches a
    // destination and ends so it floods the network
    uint16_t dest = AM_BROADCAST_ADDR;
    uint16_t TTL = 20;
    uint16_t protocol = PROTOCOL_LSA;
    uint32_t *neighbors = (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint8_t length = call NeighborDiscovery.getNumNeighbors();

    // Payload structure: first item is the number of neighbors
    // Then it alternates between neighbor id and link quality (LQ) to reach
    // that neighbor Ex: payload = [2, 1, 50, 3, 90] 2 neighbors, node 1 with
    // LQ 0.5 * 100 and 3 with LQ 0.9 * 100
    uint8_t payload[length * 2 + 1];
    uint16_t i;
    uint16_t currentNeighbor = 0;

    // The message structure sends the length of the neighbor list as the first
    // element, then the neighbor list right after
    payload[0] = length;
    for (i = 1; i < length * 2 + 1; i++) {
      if (i % 2 == 1) {
        // Insert neighbor
        payload[i] = neighbors[currentNeighbor];
      } else {
        // Insert cost
        // "Cost" is the quality of the link, prioritize better links
        // Payload accepts ints not floats, multiply by 100
        payload[i] = (call NeighborDiscovery.getNeighborLinkQuality(
                         neighbors[currentNeighbor])) *
                     100;

        currentNeighbor++;
      }
    }

    call Flooding.sendMessage(dest, TTL, protocol, payload, length * 2 + 1);
  }
}