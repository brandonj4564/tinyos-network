/**
The Interface (<name>.nc) file needs to contain a dummy command in the interface
declaration:

interface <name>{
    command void pass();
}

The Configuration (<name>C.nc) file needs both a configuration and
implementation declaration with relevant code:

configuration  <name>C{
   provides interface  <name>;
}

implementation{
    components  <name>;
     <name> =  <name>P. <name>;
}

The imPlementation file (<name>P.nc) file needs both a configuration and
implementation declaration with relevant code:

module <name>P{
   provides interface <name>;
}

implementation{
    command void <name>.pass(){}
}
*/

/*
TODO:
1. Have this module gather statistics on neighbors. If a neighbor does not
respond more than 50% of the time to beacon packets or something, it is not a
neighbor. Maybe we can do this with hashmaps.
2. Add a function that can query the neighbor list.
3. Have this module track an arbitrary number of previous beacon broadcasts, say
ten for example. Count the number of beacon responses received from each other
node in a hashmap or something. If the ratio of beacon responses to beacon
broadcasts is above some arbitrary threshold, that node is a neighbor.
4. Use one hashmap for each broadcast counted to store information about which
node responded.

Honestly I don't know exactly how to collect the neighbor statistics.
*/

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
  uses interface Hashmap<uint32_t *> as BeaconResponses;
}

implementation {
  // Variables
  // The number of beacons sent
  uint16_t sequenceNum = 0;
  // Stores arrays for 10 potential neighbors, increase storage if necessary
  // Should match the storage allocated to the BeaconResponses hashmap
  uint32_t initialReplyArray[10][5];
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
    // Threshold = 60%
    float threshold = 0.6;
    uint32_t *neighborKeys = call BeaconResponses.getKeys();

    // Index variables to use in loops
    uint16_t i;

    // Go to each hashmap entry and get an array of length 5 which stores which
    // beacons the neighbor has responded to
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t key = neighborKeys[i];
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(key));
      float denominator = 5;
      float numReceived = 0;
      uint16_t j;

      dbg(GENERAL_CHANNEL, "viewing array for node %i\n", key);

      for (j = 0; j < 5; j++) {
        dbg(GENERAL_CHANNEL, "%i\n", replyArray[j]);
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
    // I did not know that nesC requires that all variables be declared at the
    // beginning which was annoying
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload
    uint32_t *neighborKeys = call BeaconResponses.getKeys();
    uint16_t i;

    // Forgets data from the oldest beacon sent
    for (i = 0; i < call BeaconResponses.size(); i++) {
      uint32_t *replyArray =
          (uint32_t *)(call BeaconResponses.get(neighborKeys[i]));
      // dbg(GENERAL_CHANNEL, "this node's neighbor's include: %i\n",
      // neighborKeys[i]);
      replyArray[sequenceNum % 5] = 0;
    }

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, 1,
             payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);

    // Re-evaluates neighbors based on new data
    areNeighborsWorthy();
    sequenceNum++;
  }

  // Implements the function
  command void NeighborDiscovery.boot() {
    // Randomly generates a number between 0 and 499 to add to the base value of
    // 5000 ms.
    // Basically the timer will range from 5000 to 5499 ms so there is a slight
    // randomization but not too much.
    if (TOS_NODE_ID == 5) {
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
    // dbg(GENERAL_CHANNEL, "timer fired once\n");
    for (i = 0; i < size; i++) {
      // dbg(GENERAL_CHANNEL, "this node is neighbors with: %i\n", neighbor[i]);
    }

    post sendBeaconPacket();
  }

  command void NeighborDiscovery.beaconSentReceived(pack * msg) {
    uint16_t src = msg->src;
    pack beaconResponse;
    uint8_t response[1] = {0}; // Beacon packets don't really need a payload

    makePack(&beaconResponse, TOS_NODE_ID, src, 1, PROTOCOL_PINGREPLY, 1,
             response, sizeof(response));

    call SimpleSend.send(beaconResponse, src);
  }

  command void NeighborDiscovery.beaconResponseReceived(pack * msg) {
    uint16_t src = msg->src;

    // Add src of the message to array of neighbors
    // dbg(GENERAL_CHANNEL, "beacon response received from %i\n", msg->src);

    if (call BeaconResponses.contains(src)) {
      uint32_t *replyArray = (uint32_t *)(call BeaconResponses.get(src));
      if (src == 6) {
        replyArray[sequenceNum % 5] = 1;
      }

    } else {
      int i;
      for (i = 0; i < 5; i++) {
        // set to 0
        initialReplyArray[initialReplyArraySize][i] = 0;
      }

      initialReplyArray[initialReplyArraySize][sequenceNum % 5] = 1;
      call BeaconResponses.insert(src,
                                  initialReplyArray[initialReplyArraySize]);
      initialReplyArraySize++;
    }
  }

  command uint32_t *NeighborDiscovery.getNeighbors() {
    return call neighborList.getKeys();
  }

  command uint16_t NeighborDiscovery.getNumNeighbors() {
    return call neighborList.size();
  }
}