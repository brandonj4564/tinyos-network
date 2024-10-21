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
  // LSA pack struct
  // Only made this because the high level design slides said to
  typedef nx_struct packLSA {
    nx_uint16_t src;
    nx_uint16_t seq; // Sequence Number
    nx_uint8_t numNeighbors;
    nx_uint8_t payload[0];
  }
  packLSA;

  uint32_t sequenceNum = 0;

  // Wait until time has passed before allowing Dijkstra to run
  bool allowComputeRouting = 0;

  // Placeholder infinity for Dijkstra
  uint32_t maxCost = 10000;

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
      routingArray[i][0] = 0;
      routingArray[i][1] = -1;
      routingArray[i][2] = maxCost;
      routingArray[i][3] = -1;
      routingArray[i][4] = maxCost;
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

    // Store the indices for the structure of routingArray as variables
    // This improves code readability
    uint8_t activate = 0;
    uint8_t nextHop = 1;
    uint8_t cost = 2;
    uint8_t backupHop = 3;
    uint8_t backupCost = 4;

    // Initializing the cost array, start with all nodes being "infinity"
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      tempRoutingArray[i][activate] = neighborsArray[i][activate];
      unconsidered[i] = neighborsArray[i][activate];
      tempRoutingArray[i][nextHop] = -1;
      tempRoutingArray[i][cost] = maxCost;
      tempRoutingArray[i][backupHop] = -1;
      tempRoutingArray[i][backupCost] = maxCost;
    }

    tempRoutingArray[TOS_NODE_ID][nextHop] = TOS_NODE_ID;
    tempRoutingArray[TOS_NODE_ID][cost] = 0;
    tempRoutingArray[TOS_NODE_ID][backupHop] = TOS_NODE_ID;
    tempRoutingArray[TOS_NODE_ID][backupCost] = 0;

    // This node's immediate neighbors have their cost overwritten
    for (i = 0; i < numNeighbors; i++) {
      uint32_t n = immNeighbors[i];

      if (n != disabledNeighbor) {
        uint32_t startingCost = calcLinkToCost(
            call NeighborDiscovery.getNeighborLinkQuality(n) * 100);
        // dbg(GENERAL_CHANNEL, "cost: %i\n", startingCost);
        tempRoutingArray[n][cost] = startingCost;
        // tempRoutingArray[n][backupCost] = maxCost;

        // Next hop
        tempRoutingArray[n][nextHop] = n;
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
        if (unconsidered[i] == 1 && tempRoutingArray[i][cost] <= lowValue) {
          currentLow = i;
          lowValue = tempRoutingArray[i][cost];
        }
      }

      unconsidered[currentLow] = 0;
      // current low is equal to next node
      // get the neighbors of that node and add it to cost in table.

      lowestCostNumNeighbors = neighborsArray[currentLow][1];

      for (j = 1; j < lowestCostNumNeighbors + 1; j++) {
        // Remember: Structure of the neighborsArray
        // [active?, numNeighbors, neighbor1, LQ1, neighbor2, LQ2...]
        // [1, 2, 5, 75, 7, 20]
        uint32_t currentNode = neighborsArray[currentLow][j * 2];
        // adds cost of current low node to the ones of the neighbor nodes
        // to get the cost from currentNode(TOS_NOde...).
        int tempCost = tempRoutingArray[currentLow][cost] +
                       calcLinkToCost(neighborsArray[currentLow][j * 2 + 1]);

        tempRoutingArray[currentLow][activate] = 1;

        if (tempCost < tempRoutingArray[currentNode][cost]) {

          // store the next hop from currentNode, working backwords
          tempRoutingArray[currentNode][nextHop] =
              tempRoutingArray[currentLow][nextHop];
          tempRoutingArray[currentNode][cost] = tempCost;
        }
      }
    }

    // Transfer tempRoutingArray into routingArray
    for (i = 0; i < neighborsArraySizeLimit; i++) {
      int tempCost = tempRoutingArray[i][cost];
      int tempBackupCost = tempRoutingArray[i][backupCost];
      int tempNextHop = tempRoutingArray[i][nextHop];
      int tempBackupHop = tempRoutingArray[i][backupHop];

      if (tempRoutingArray[i][activate] != 1) {
        continue;
      }

      if (tempCost <= routingArray[i][cost]) {

        if (routingArray[i][nextHop] != tempNextHop) {
          routingArray[i][backupCost] = routingArray[i][cost];
          routingArray[i][backupHop] = routingArray[i][nextHop];
        }

        routingArray[i][cost] = tempCost;
        routingArray[i][nextHop] = tempNextHop;
        routingArray[i][activate] = 1;

      } else if (tempCost <= routingArray[i][backupCost] &&
                 routingArray[i][nextHop] != tempNextHop) {
        // Basically only update backup hop if it is different than next hop
        routingArray[i][backupCost] = tempCost;
        routingArray[i][backupHop] = tempNextHop;
        routingArray[i][activate] = 1;
      }

      if (tempBackupCost <= routingArray[i][backupCost] &&
          tempBackupHop != routingArray[i][nextHop]) {

        routingArray[i][backupCost] = tempBackupCost;
        routingArray[i][backupHop] = tempBackupHop;
        routingArray[i][activate] = 1;
      }
    }
  }

  task void computeRoutingTable() {
    // Store the indices for the structure of routingArray as variables
    // This improves code readability
    uint8_t activate = 0;
    uint8_t nextHop = 1;
    // uint8_t cost = 2;
    // uint8_t backupHop = 3;
    // uint8_t backupCost = 4;

    uint32_t *immNeighbors =
        (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint32_t numNeighbors = call NeighborDiscovery.getNumNeighbors();

    uint32_t i;

    resetRoutingTable();
    runDijkstra(immNeighbors, numNeighbors, -1);

    // Re-run Dijkstra to compute backup hops
    // Disable one neighbor of this node, then rerun Dijkstra
    for (i = 0; i < numNeighbors; i++) {
      int disabledNeighbor = immNeighbors[i];
      runDijkstra(immNeighbors, numNeighbors, disabledNeighbor);
    }

    /*
    Packet encapsulation and decapsulation -- MOST IMPORTANT PART TO LOOK OVER

    neighbor discovery: create new headers
    Paul, Ryan
    Ask:
    How do you pass the payload from InternetProtocol to the Ping application?
    Am I doing the packet encapsulation and header stuff correct?
    Are there any strict rules regarding the PROTOCOLs in protocol.h or am I
    free to define them as I require?
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
    packLSA *lsa = (packLSA *)msg->payload;
    uint16_t sizeLSA = lsa->numNeighbors * 2;
    uint8_t *payload = (uint8_t *)(lsa->payload);
    uint16_t src = lsa->src;
    uint16_t seq = lsa->seq;

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
    // dbg(GENERAL_CHANNEL, "LSA payload length: %i\n", sizeLSA);
    // for (i = 0; i < sizeLSA; i++) {
    //   dbg(GENERAL_CHANNEL, "Contents of Payload: %i\n", payload[i]);
    // }

    if (src >= neighborsArraySizeLimit) {
      dbg(GENERAL_CHANNEL,
          "Cannot store node %i's neighbor list! Increase "
          "neighborsArraySizeLimit!\n",
          lsa->src);
      return;
    }

    neighborsArray[src][0] = 1; // This node's neighbors are tracked
    neighborsArray[src][1] = lsa->numNeighbors;
    for (i = 0; i < sizeLSA; i++) {
      neighborsArray[src][i + 2] = payload[i];
    }

    if (allowComputeRouting) {
      post computeRoutingTable();
    }
  }

  void makeLSA(packLSA * Package, uint16_t src, uint16_t seq, uint8_t * payload,
               uint8_t length) {
    Package->src = src;
    Package->seq = seq;
    Package->numNeighbors = length / 2;
    memcpy(Package->payload, payload, length);
  }

  command void LinkState.sendLSA() {
    // Taken directly from packet.h
    // uint8_t PACKET_HEADER_LENGTH = 8;
    // uint8_t PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH;
    packLSA lsa;

    // Having dest = AM_BROADCAST_ADDR means the message never
    // reaches a destination and ends so it floods the network
    uint16_t dest = AM_BROADCAST_ADDR;
    uint16_t TTL = 10;
    uint16_t protocol = PROTOCOL_LINKSTATE;
    uint32_t *neighbors = (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint8_t length = 2 * call NeighborDiscovery.getNumNeighbors();

    // Payload structure: [neighbor1, LQ1, neighbor2, LQ2...]
    uint8_t lsaSize = sizeof(packLSA) + (length * sizeof(uint8_t));
    uint8_t lsaPayload[length];
    uint8_t normalPayload[PACKET_MAX_PAYLOAD_SIZE];
    uint16_t i;
    uint16_t currentNeighbor = 0;

    // Ensure the total size of packLSA fits in the payload of pack
    // Max packet size for us is 20 bytes, subtract our overhead (5 bytes) and
    // we get 15 bytes.
    // We only have 15 bytes for our payload, which is 15 spots. This means we
    // can send a max of SEVEN neighbor-LQ tuples per packet.
    if (lsaSize > PACKET_MAX_PAYLOAD_SIZE) {
      // TODO: Fragment the packet, so that you can send more than 7 neighbors
      dbg(GENERAL_CHANNEL, "Error: LSA is too large to fit in payload!\n");
      return;
    }

    for (i = 0; i < length; i++) {
      if (i % 2 == 0) {
        // Insert neighbor
        lsaPayload[i] = neighbors[currentNeighbor];
      } else {
        // Insert cost
        // "Cost" is the quality of the link, prioritize better links
        // Payload accepts ints not floats, multiply by 100
        lsaPayload[i] = (call NeighborDiscovery.getNeighborLinkQuality(
                            neighbors[currentNeighbor])) *
                        100;

        currentNeighbor++;
      }
    }

    makeLSA(&lsa, TOS_NODE_ID, sequenceNum, lsaPayload, length);
    sequenceNum++;

    // Copy the entire packLSA into the payload of pack
    memcpy(normalPayload, (void *)(&lsa), lsaSize);

    call Flooding.sendMessage(dest, TTL, protocol, normalPayload, lsaSize);
  }
}