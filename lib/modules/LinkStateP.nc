module LinkStateP {
  provides interface LinkState;

  uses interface NeighborDiscovery;

  uses interface Flooding;

  uses interface Boot;

  uses interface Timer<TMilli> as CacheReset;
  uses interface Timer<TMilli> as InitialDelay;

  uses interface Hashmap<uint16_t> as Cache;
}

implementation {
  /*
  IMPORTANT!!!
  To demonstrate your solution, you should be able to call a function in your
  Python run script to print out all of the link state advertisements you used
  to compute the routing table, and to print the contents of the routing table.
  You may find this more convenient than logging the entire routing table after
  every change. The command should be: def cmdRouteDMP(destination)
  */

  // Wait until time has passed before allowing Dijkstra to run
  bool allowComputeRouting = 0;

  uint32_t neighborsArraySizeLimit = 30;

  uint32_t neighborsArray[30]
                         [30]; // change this if neighborsArraySizeLimit changes

  uint32_t routingArraySizeLimit = 5;
  int routingArray[30][5]; // change second part if routingArraySizeLimit
                           // changes
  // Routing Array Structure:
  // [valid?, next hop, cost, backup next hop, backup cost]
  // [1, 2, 0.8, 5, 0.9]

  void resetRoutingTable() {
    // Called whenever the table must be recomputed
    uint32_t i;
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      uint32_t j;
      routingArray[i][0] = 0;
      for (j = 1; j < routingArraySizeLimit; j++) {
        // initialization
        routingArray[i][j] = -1;
      }
    }
  }

  event void Boot.booted() {
    // Start the module
    resetRoutingTable();

    call CacheReset.startPeriodic(200000);

    // This should be longer than the timer for NeighborDiscovery, which
    // currently is about 11000 ms
    // Please remember to change this value if NeighborDiscovery timer is
    // changed!
    call InitialDelay.startOneShot(12000);
  }

  uint32_t calcLinkToCost(int link) {
    // Link is the link quality, a value between 0 and 1
    // Realistically, because there is a threshold, the link quality is a
    // value between 50 and 100 (percent)

    return (100 + 350 * ((100 - (float)link) / 100));
    // In practice, this calc returns about 110 at lowest and 275 at highest
    // So a perfect connection link is about 110 cost
  }

  void runDijkstra(uint32_t * immNeighbors, uint32_t numNeighbors,
                   int disabledNeighbor) {
    uint32_t unconsidered[neighborsArraySizeLimit];
    int tempRoutingArray[neighborsArraySizeLimit][routingArraySizeLimit];

    uint32_t i;

    // Placeholder infinity for Dijkstra
    uint32_t maxCost = 10000;

    // Store the indices for the structure of routingArray as variables
    // This improves code readability
    uint8_t activate = 0;
    uint8_t nextHop = 1;
    uint8_t cost = 2;
    uint8_t backupHop = 3;
    uint8_t backupCost = 4;

    // Initializing the cost array, start with all nodes being "infinity"
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (neighborsArray[i][0] == 1) {
        routingArray[i][cost] = maxCost;
        routingArray[i][backupCost] = maxCost;
        // Creates copy so we can remove later
        unconsidered[i] = 1;
      } else {
        unconsidered[i] = 0;
      }
    }

    routingArray[TOS_NODE_ID][nextHop] = TOS_NODE_ID;
    routingArray[TOS_NODE_ID][cost] = 0;
    routingArray[TOS_NODE_ID][backupHop] = TOS_NODE_ID;
    routingArray[TOS_NODE_ID][backupCost] = 0;

    // This node's immediate neighbors have their cost overwritten
    for (i = 0; i < numNeighbors; i++) {
      uint32_t n = immNeighbors[i];

      if (n != disabledNeighbor) {
        uint32_t startingCost = calcLinkToCost(
            call NeighborDiscovery.getNeighborLinkQuality(n) * 100);
        // dbg(GENERAL_CHANNEL, "cost: %i\n", startingCost);
        routingArray[n][cost] = startingCost;
        // routingArray[n][backupCost] = maxCost;

        // Next hop
        routingArray[n][nextHop] = n;
      }
      unconsidered[n] = 1;
    }

    while (1) {
      uint32_t emptyCheck = 0;
      uint32_t lowValue = maxCost; // low cost comparison
      uint32_t currentLow;         // lowest cost node id
      uint32_t j;
      uint32_t lowestCostNumNeighbors;

      // checks if unconsidered list is empty
      for (i = 0; i < neighborsArraySizeLimit; i++) {
        emptyCheck += unconsidered[i];
      }
      if (emptyCheck == 0) {
        break;
      }

      for (i = 0; i < neighborsArraySizeLimit; i++) {
        if (unconsidered[i] == 1 && routingArray[i][cost] <= lowValue) {
          currentLow = i;
          lowValue = routingArray[i][cost];
        }
      }

      unconsidered[currentLow] = 0;
      // current low is equal to next node
      // get the neighbors of that node and add it to cost in table.

      lowestCostNumNeighbors = neighborsArray[currentLow][1];

      if (lowestCostNumNeighbors == 1 &&
          neighborsArray[currentLow][3] < maxCost) {
        // Only one neighbor means only one path to get to that node
        // This breaks my backup hop algorithm so I need a special case
        // I simply copy the backup hop of the sole neighbor
        int soleNeighbor = neighborsArray[currentLow][2];
        int soleNeighborLink = neighborsArray[currentLow][3];
        routingArray[currentLow][backupHop] =
            routingArray[soleNeighbor][backupHop];

        routingArray[currentLow][backupCost] =
            routingArray[soleNeighbor][backupCost] +
            calcLinkToCost(soleNeighborLink);
      }

      for (j = 1; j < lowestCostNumNeighbors + 1; j++) {
        // Remember: Structure of the neighborsArray
        // [active?, numNeighbors, neighbor1, LQ1, neighbor2, LQ2...]
        // [1, 2, 5, 75, 7, 20]
        uint32_t currentNode = neighborsArray[currentLow][j * 2];
        // adds cost of current low node to the ones of the neighbor nodes
        // to get the cost from currentNode(TOS_NOde...).
        int tempCost = routingArray[currentLow][cost] +
                       calcLinkToCost(neighborsArray[currentLow][j * 2 + 1]);

        routingArray[currentLow][activate] = 1;

        if (tempCost < routingArray[currentNode][cost]) {

          // store the next hop from currentNode, working backwords
          if (routingArray[currentLow][nextHop] !=
              routingArray[currentNode][nextHop]) {

            routingArray[currentNode][backupCost] =
                routingArray[currentNode][cost];

            // Swap the backup next hop with the current next hop
            routingArray[currentNode][backupHop] =
                routingArray[currentNode][nextHop];
          }

          routingArray[currentNode][nextHop] =
              routingArray[currentLow][nextHop];
          routingArray[currentNode][cost] = tempCost;
        } else if (tempCost < routingArray[currentNode][backupCost]) {
          // TODO: Make backup next hop actually work

          if (routingArray[currentLow][nextHop] !=
              routingArray[currentNode][nextHop]) {
            // Only update backup next hop if it is different from the normal
            // next hop
            routingArray[currentNode][backupCost] = tempCost;
            routingArray[currentNode][backupHop] =
                routingArray[currentLow][nextHop];
          }
        }
      }
    }

    // Transfer tempRoutingArray into routingArray
    // for (i = 0; i < neighborsArraySizeLimit; i++) {
    //   if (tempRoutingArray[i][activate] != 1) {
    //     continue;
    //   }

    //   if (tempRoutingArray[i][cost] <= routingArray[i][cost]) {

    //     routingArray[i][backupCost] = routingArray[i][cost];
    //     routingArray[i][backupHop] = routingArray[i][nextHop];

    //     routingArray[i][cost] = tempRoutingArray[i][cost];
    //     routingArray[i][nextHop] = tempRoutingArray[i][nextHop];

    //   } else if (tempRoutingArray[i][cost] <= routingArray[i][backupCost]) {

    //     routingArray[i][backupCost] = tempRoutingArray[i][cost];
    //     routingArray[i][backupHop] = tempRoutingArray[i][nextHop];

    //   } else if (tempRoutingArray[i][backupCost] <=
    //              routingArray[i][backupCost]) {

    //     routingArray[i][backupCost] = tempRoutingArray[i][backupCost];
    //     routingArray[i][backupHop] = tempRoutingArray[i][backupHop];
    //   }
    // }
  }

  task void computeRoutingTable() {
    // Store the indices for the structure of routingArray as variables
    // This improves code readability
    uint8_t activate = 0;
    uint8_t nextHop = 1;
    uint8_t cost = 2;
    uint8_t backupHop = 3;
    uint8_t backupCost = 4;

    uint32_t maxCost = 10000;

    uint32_t *immNeighbors =
        (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint32_t numNeighbors = call NeighborDiscovery.getNumNeighbors();

    uint32_t i;

    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (neighborsArray[i][0] == 1) {
        routingArray[i][activate] = 1;
        routingArray[i][cost] = maxCost;
        routingArray[i][backupCost] = maxCost;
      }
    }

    resetRoutingTable();
    runDijkstra(immNeighbors, numNeighbors, -1);

    // Re-run Dijkstra to compute backup hops
    // Disable one neighbor of this node, then rerun Dijkstra
    for (i = 0; i < numNeighbors; i++) {
      int disabledNeighbor = immNeighbors[i];
      // runDijkstra(immNeighbors, numNeighbors, disabledNeighbor);
    }

    /*
    Packet encapsulation and decapsulation -- MOST IMPORTANT PART TO LOOK OVER

    neighbor discovery: create new headers
    Paul, Ryan
    */

    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (routingArray[i][activate] == 1 && routingArray[i][nextHop] == -1) {
        // Deactivate dead nodes
        routingArray[i][activate] = 0;
      }
    }
  }

  command int LinkState.getNextHop(int dest, bool backup) {
    // Check if dest in bounds
    if (dest < 0 || dest >= neighborsArraySizeLimit) {
      return -1;
    }

    if (!routingArray[dest][0]) {
      // Routing table not activated for this destination
      return -1;
    } else {
      // Routing array structure:
      // [active?, next hop, cost, backup next hop, backup cost]
      int nextHop = routingArray[dest][1];
      if (backup) {
        nextHop = routingArray[dest][3];
      }

      return nextHop;
    }
  }

  command int LinkState.getCost(int dest, bool backup) {
    // Check if dest in bounds
    if (dest < 0 || dest >= neighborsArraySizeLimit) {
      return -1;
    }

    if (!routingArray[dest][0]) {
      // Routing table not activated for this destination
      return -1;
    } else {
      // Routing array structure:
      // [active?, next hop, cost, backup next hop, backup cost]
      int cost = routingArray[dest][2];
      if (backup) {
        cost = routingArray[dest][4];
      }

      return cost;
    }
  }

  command void LinkState.getActiveRoutes(int *routes) {
    int i;
    int currentIndex;

    currentIndex = 0;
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (routingArray[i][0] == 1) {
        routes[currentIndex] = i;
        currentIndex++;
      }
    }
  }

  command int LinkState.getNumActiveRoutes() {
    int i;
    int num = 0;
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (routingArray[i][0] == 1) {
        num++;
      }
    }

    return num;
  }

  command void LinkState.printAllLSA() {
    int i;
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      if (neighborsArray[i][0] == 1) {
        // Remember: Structure of the neighborsArray
        // [active?, numNeighbors, neighbor1, LQ1, neighbor2, LQ2...]
        // [1, 2, 5, 75, 7, 20]
        int numNeighbors = neighborsArray[i][1];
        int j;

        dbg(GENERAL_CHANNEL, "LSA from node %i\n", i);
        for (j = 1; j < numNeighbors + 1; j++) {
          dbg(GENERAL_CHANNEL, "Neighbor: %i | Link Quality: %i\n",
              neighborsArray[i][j * 2], neighborsArray[i][j * 2 + 1]);
        }
      }
    }
  }

  event void CacheReset.fired() {
    uint32_t *tableKeys = (uint32_t *)(call Cache.getKeys());
    uint16_t tableSize = call Cache.size();
    uint16_t i;

    for (i = 0; i < tableSize; i++) {
      uint32_t key = tableKeys[i];
      call Cache.remove(key);
    }
  }

  // Only begin running Dijkstra after learning about the complete topology
  event void InitialDelay.fired() { allowComputeRouting = 1; }

  event void NeighborDiscovery.listUpdated() {
    // Re-send LSA and recompute routing table
    call LinkState.sendLSA();

    if (allowComputeRouting) {
      post computeRoutingTable();
    }
  }

  command void LinkState.receiveLSA(pack * msg) {
    // recieve neighbor list from other nodes
    // Add neighbor list to networkTopo configuring it to it's sender node
    uint16_t sizeLSA = msg->payload[0] * 2 + 1;
    uint8_t *payload = (uint8_t *)(msg->payload);
    uint16_t src = msg->src;
    uint16_t seq = msg->seq;

    uint16_t i;

    // Check cache for higher seq
    if (call Cache.contains(src)) {
      if (seq <= call Cache.get(src)) {
        return; // Lower seq
      } else {
        call Cache.remove(src); // Update seq
        call Cache.insert(src, seq);
      }
    } else {
      call Cache.insert(src, seq); // First time receiving
    }

    // dbg(GENERAL_CHANNEL, "LSA from %i\n", src);
    // for (i = 0; i < sizeLSA; i++) {
    //   dbg(GENERAL_CHANNEL, "Contents of Payload: %i\n", payload[i]);
    // }

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

    if (allowComputeRouting) {
      post computeRoutingTable();
    }
  }

  command void LinkState.sendLSA() {
    // Having dest = AM_BROADCAST_ADDR means the message never reaches a
    // destination and ends so it floods the network
    uint16_t dest = AM_BROADCAST_ADDR;
    uint16_t TTL = 20;
    uint16_t protocol = PROTOCOL_LINKSTATE;
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