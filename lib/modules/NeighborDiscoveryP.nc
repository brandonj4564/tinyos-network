module NeighborDiscoveryP {
  // Provides shows the interface we are implementing. See
  // lib/interface/NeighborDiscovery.nc to see what funcitons we need to
  // implement.
  provides interface NeighborDiscovery;

  uses interface Timer<TMilli> as beaconTimer;
  uses interface Timer<TMilli> as CacheReset;
  uses interface SimpleSend;
  uses interface Random;
  uses interface Boot;

  // Hashmap
  uses interface Hashmap<float> as neighborList;

  // This hashmap takes in a node id as a key and stores the pointer of an array
  // of length 5 as the value. This array stores data on the past 5 beacon
  // packets sent. If the array is [0, 1, 1, 0, 1], that means the node that
  // corresponds to this array responded to 3 out of the past 5 beacons.
  uses interface Hashmap<uint32_t *> as BeaconResponses;

  // Caches to check if the sequence num of a beacon sent or response message
  // is lower than previously seen
  uses interface Hashmap<uint32_t> as BeaconSentCache;
  uses interface Hashmap<uint32_t> as BeaconResponseCache;
}

implementation {
  // Variables

  // The number of past beacons tracked. Originally 5. If this variable is
  // changed, for every comment below that mentions 5 beacons, mentally
  // substitute the new number.
  uint16_t beaconsTracked = 10;

  // The sequence number doubles as a way to keep track of which array we are
  // currently using to track which nodes have responded to our beacon. This is
  // done by calculating sequenceNum % 5.
  uint8_t sequenceNum = 0;

  // Stores arrays for 10 potential neighbors, increase storage if necessary
  // Should match the storage allocated to the BeaconResponses hashmap
  uint32_t initialReplyArraySizeLimit = 10;
  uint32_t initialReplyArray[10][10]; // change this if either size limit or
                                      // beacons tracked changes
  uint16_t initialReplyArraySize = 0;

  // Commands and Functions

  void makePack(pack * Package, uint8_t src, uint8_t dest, uint8_t TTL,
                uint8_t protocol, uint8_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  // Send the beacon packet to all neighbors
  task void sendBeaconPacket() {
    // (Note: remember that nesC vars need to be declared in the start)
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload
    uint32_t *neighborKeys = call BeaconResponses.getKeys();
    uint16_t i;
    uint8_t TTL = 1;

    sequenceNum++;

    // Forgets data from the oldest beacon sent, assumes all beacons did not
    // respond
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t *replyArray =
          (uint32_t *)(call BeaconResponses.get(neighborKeys[i]));
      replyArray[sequenceNum % beaconsTracked] = 0;
    }

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, TTL, PROTOCOL_BEACON,
             sequenceNum, payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);
  }

  event void Boot.booted() {
    // Randomly generates a number between to add to the base value.
    // Basically the timer will range from 10000 to 10999 ms so there is a
    // slight randomization but not too much.
    uint32_t timeInMS = (call Random.rand16() % 1000) + 10000;

    post sendBeaconPacket();
    call beaconTimer.startPeriodic(timeInMS);

    call CacheReset.startPeriodic(200000);
  }

  task void areNeighborsWorthy() {
    // TODO: Change this to an exponential weighted moving average, should be
    // easy
    float threshold = 0.5;
    float alpha = 0.3; // Smoothing factor for EWMA

    uint32_t *neighborKeys = call BeaconResponses.getKeys();

    // Bool variable, has the neighbor list been updated?
    uint8_t listChanged = 0;

    // Index variables to use in loops
    uint16_t i;

    // Go to each hashmap entry and get an array of length 10 which stores which
    // beacons the neighbor has responded to
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t key = neighborKeys[i];
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(key));
      float ewmaValue = 0;
      uint16_t j;

      // dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: Viewing response array for node %i.\n
      // ",
      //     key);

      for (j = 0; j < beaconsTracked; j++) {
        // dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: %i\n", replyArray[j]);

        // Start with the oldest response which is sequenceNum % beaconsTracked,
        // then move forward with EWMA This is only guaranteed to be the oldest
        // response if we post this task immediately after incrementing
        // sequenceNum
        ewmaValue = alpha * replyArray[(sequenceNum + j) % beaconsTracked] +
                    (1 - alpha) * ewmaValue;
      }

      if (ewmaValue >= threshold) {
        if (!(call neighborList.contains(key))) {
          call neighborList.insert(key, ewmaValue);
          listChanged = 1;
        } else {
          float oldEWMAVal = call neighborList.get(key);
          float diff = ewmaValue - oldEWMAVal;

          if (diff >= 0.18 || diff <= -0.18) {
            // If the difference in link quality is large enough, notify the
            // network
            call neighborList.remove(key);
            call neighborList.insert(key, ewmaValue);
            listChanged = 1;
          }
        }
      } else {
        if (call neighborList.contains(key)) {
          call neighborList.remove(key);
          listChanged = 1;
        }
      }
    }

    if (listChanged) {
      signal NeighborDiscovery.listUpdated();
    }
  }

  task void resetCache() {
    // Reset the soft state of both caches occasionally
    // Ensures that, if a node dies, it can still send messages later by
    // forgetting previously high sequences

    uint32_t *sentKeys = (uint32_t *)(call BeaconSentCache.getKeys());
    uint16_t sentSize = call BeaconSentCache.size();
    uint32_t *responseKeys = (uint32_t *)(call BeaconResponseCache.getKeys());
    uint16_t responseSize = call BeaconResponseCache.size();

    uint16_t i;

    // dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: Clearing caches...\n");

    for (i = 0; i < sentSize; i++) {
      uint32_t key = sentKeys[i];
      call BeaconSentCache.remove(key);
    }

    for (i = 0; i < responseSize; i++) {
      uint32_t key = responseKeys[i];
      call BeaconResponseCache.remove(key);
    }
    // God I hope this doesn't have concurrency issues
  }

  event void beaconTimer.fired() {
    // test: print out all neighbors in the neighbor list

    // uint32_t *neighbor = (uint32_t *)(call NeighborDiscovery.getNeighbors());
    // int size = call NeighborDiscovery.getNumNeighbors();
    // int i;
    //
    // for (i = 0; i < size; i++) {
    //   dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: This node is neighbors with: %i\n",
    //       neighbor[i]);
    // }

    post sendBeaconPacket();
  }

  event void CacheReset.fired() {
    // Timer interrupt handlers should be as fast as possible, so put code in a
    // task which can be executed concurrently
    post resetCache();
  }

  command void NeighborDiscovery.beaconSentReceived(pack * msg) {
    uint16_t src = msg->src;
    // Send a beacon reply message with the same sequence number as the beacon
    // packet
    uint16_t seq = msg->seq;
    pack beaconResponse;
    uint8_t response[1] = {0}; // Beacon packets don't need a payload

    bool validToSend = 1;
    if (call BeaconSentCache.contains(src)) {
      // validToSend is only false if cached seq is not smaller than newly
      // received seq
      validToSend = call BeaconSentCache.get(src) < seq;
    } else {
      call BeaconSentCache.insert(src, seq);
    }

    if (validToSend) {
      makePack(&beaconResponse, TOS_NODE_ID, src, 1, PROTOCOL_BEACONREPLY, seq,
               response, sizeof(response));

      call SimpleSend.send(beaconResponse, src);
    } else {
      // seq not higher than one in cache
      dbg(NEIGHBOR_CHANNEL,
          "NEIGHBOR: Node %i sent an outdated beacon packet.\n", src);
    }
  }

  command void NeighborDiscovery.beaconResponseReceived(pack * msg) {
    uint16_t src = msg->src;
    uint16_t seq = msg->seq;

    bool validToReceive = 1;
    if (call BeaconResponseCache.contains(src)) {
      // validToReceive is only false if cached seq is not smaller than newly
      // received seq
      validToReceive = call BeaconResponseCache.get(src) < seq;
    } else {
      call BeaconResponseCache.insert(src, seq);
    }

    if (!validToReceive) {
      // seq not higher than one in cache
      dbg(NEIGHBOR_CHANNEL,
          "NEIGHBOR: Node %i sent an outdated beacon response.\n", src);
      return;
    }

    // dbg(NEIGHBOR_CHANNEL, "NEIGHBOR: beacon response received from
    // %i\n", msg->src);
    if (call BeaconResponses.contains(src)) {
      // If the table already has an entry for the src node, get the
      // associated array and update the current array value to 1 since it has
      // replied
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(src));

      replyArray[sequenceNum % beaconsTracked] = 1;

      // Re-evaluates neighbors based on new stats
      post areNeighborsWorthy();

    } else {
      // Src node not in table, create a new array for it and store it in the
      // initialReplyArray matrix
      if (initialReplyArraySize < initialReplyArraySizeLimit) {
        // Ensure the initialReplyArray has enough space to store another
        // array

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

        // Re-evaluates neighbors based on new stats
        post areNeighborsWorthy();

      } else {
        // dbg(NEIGHBOR_CHANNEL,
        //     "NEIGHBOR: Node %i cannot be stored as a neighbor! "
        //     "Increase initialReplyArray size!\n",
        //     src);
      }
    }
  }

  command uint32_t *NeighborDiscovery.getNeighbors() {
    return call neighborList.getKeys();
  }

  command float NeighborDiscovery.getNeighborLinkQuality(uint32_t neighbor) {
    return call neighborList.get(neighbor);
  }

  command uint16_t NeighborDiscovery.getNumNeighbors() {
    return call neighborList.size();
  }
}