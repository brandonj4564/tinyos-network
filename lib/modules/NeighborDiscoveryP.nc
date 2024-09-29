module NeighborDiscoveryP {
  // Provides shows the interface we are implementing. See
  // lib/interface/NeighborDiscovery.nc to see what funcitons we need to
  // implement.
  provides interface NeighborDiscovery;

  uses interface Timer<TMilli> as beaconTimer;
  uses interface SimpleSend;
  uses interface Random;

  // Hashmap
  uses interface Hashmap<uint16_t> as neighborList;

  // This hashmap takes in a node id as a key and stores the pointer of an array
  // of length 5 as the value. This array stores data on the past 5 beacon
  // packets sent. If the array is [0, 1, 1, 0, 1], that means the node that
  // corresponds to this array responded to 3 out of the past 5 beacons.
  uses interface Hashmap<uint32_t *> as BeaconResponses;
}

implementation {
  // Variables

  // The number of past beacons tracked. Originally 5. If this variable is
  // changed, for every comment below that mentions 5 beacons, mentally
  // substitute the new number.
  uint16_t beaconsTracked = 5;

  // The sequence number doubles as a way to keep track of which array we are
  // currently using to track which nodes have responded to our beacon. This is
  // done by calculating sequenceNum % 5.
  uint16_t sequenceNum = 0;

  // Stores arrays for 10 potential neighbors, increase storage if necessary
  // Should match the storage allocated to the BeaconResponses hashmap
  uint32_t initialReplyArraySizeLimit = 10;
  uint32_t initialReplyArray[10][5]; // change this if either size limit or
                                     // beacons tracked changes
  uint16_t initialReplyArraySize = 0;

  // Commands and Functions

  void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL,
                uint16_t protocol, uint16_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  void areNeighborsWorthy() {
    // Threshold = 60% out of the past 5, so 3/5
    float threshold = 0.6;
    uint32_t *neighborKeys = call BeaconResponses.getKeys();

    // Index variables to use in loops
    uint16_t i;

    // Go to each hashmap entry and get an array of length 5 which stores which
    // beacons the neighbor has responded to
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t key = neighborKeys[i];
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(key));
      float denominator = beaconsTracked;
      float numReceived = 0;
      uint16_t j;

      dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: Viewing response array for node %i.\n",
          key);

      for (j = 0; j < beaconsTracked; j++) {
        dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: %i\n", replyArray[j]);
        numReceived += replyArray[j];
      }

      if (numReceived / denominator >= threshold) {
        if (!(call neighborList.contains(key))) {
          call neighborList.insert(key, numReceived / denominator);
        } else {
          call neighborList.remove(key);
          call neighborList.insert(key, numReceived / denominator);
        }
      } else {
        if (call neighborList.contains(key)) {
          call neighborList.remove(key);
        }
      }
    }
  }

  // Send the beacon packet to all neighbors
  task void sendBeaconPacket() {
    // (Note: remember that nesC vars need to be declared in the start)
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload
    uint32_t *neighborKeys = call BeaconResponses.getKeys();
    uint16_t i;

    sequenceNum++;
    // Re-evaluates neighbors based on new stats
    areNeighborsWorthy();

    // Forgets data from the oldest beacon sent, assumes all beacons did not
    // respond
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t *replyArray =
          (uint32_t *)(call BeaconResponses.get(neighborKeys[i]));
      replyArray[sequenceNum % beaconsTracked] = 0;
    }

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING,
             sequenceNum, payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);
  }

  // Implements the function
  command void NeighborDiscovery.start() {
    // Randomly generates a number between 0 and 499 to add to the base value of
    // 5000 ms.
    // Basically the timer will range from 5000 to 5499 ms so there is a slight
    // randomization but not too much.
    if (TOS_NODE_ID == 9) {
      // remove this if statement later, this is just to test neighbor discovery
      // on only node 5
      uint32_t timeInMS = (call Random.rand16() % 1000) + 10000;
      call beaconTimer.startPeriodic(timeInMS);
    }
  }

  event void beaconTimer.fired() {
    // test: print out all neighbors in the neighbor list
    uint32_t *neighbor = (uint32_t *)(call NeighborDiscovery.getNeighbors());
    int size = call NeighborDiscovery.getNumNeighbors();
    int i;

    for (i = 0; i < size; i++) {
      dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: This node is neighbors with: %i\n",
          neighbor[i]);
    }

    post sendBeaconPacket();
  }

  command void NeighborDiscovery.beaconSentReceived(pack * msg) {
    uint16_t src = msg->src;
    pack beaconResponse;
    uint8_t response[1] = {0}; // Beacon packets don't need a payload

    makePack(&beaconResponse, TOS_NODE_ID, src, 1, PROTOCOL_PINGREPLY, 1,
             response, sizeof(response));

    call SimpleSend.send(beaconResponse, src);
  }

  command void NeighborDiscovery.beaconResponseReceived(pack * msg) {
    uint16_t src = msg->src;

    // dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: beacon response received from
    // %i\n", msg->src);

    if (call BeaconResponses.contains(src)) {
      // If the table already has an entry for the src node, get the associated
      // array and update the current array value to 1 since it has replied
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(src));

      replyArray[sequenceNum % beaconsTracked] = 1;

    } else {
      // Src node not in table, create a new array for it and store it in the
      // initialReplyArray matrix
      if (initialReplyArraySize < initialReplyArraySizeLimit) {
        // Ensure the initialReplyArray has enough space to store another array

        int i;
        for (i = 0; i < beaconsTracked; i++) {
          // set to 0
          initialReplyArray[initialReplyArraySize][i] = 0;
        }

        initialReplyArray[initialReplyArraySize][sequenceNum % beaconsTracked] =
            1;
        call BeaconResponses.insert(src,
                                    initialReplyArray[initialReplyArraySize]);
        initialReplyArraySize++;
      } else {
        dbg(NEIGHBOR_CHANNEL,
            "NEIGHBOR: Node %i cannot be stored as a neighbor! "
            "Increase initialReplyArray size!\n",
            src);
      }
    }
  }

  command uint32_t *NeighborDiscovery.getNeighbors() {
    return call neighborList.getKeys();
  }

  command uint16_t NeighborDiscovery.getNumNeighbors() {
    return call neighborList.size();
  }
}