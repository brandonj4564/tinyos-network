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
}

implementation {

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

  // Implements the function
  command void NeighborDiscovery.start() {
    // ms, so 4 seconds
    call beaconTimer.startPeriodic(4000);
  }

  event void beaconTimer.fired() {
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, 1,
             payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);
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
    // Add src of the message to array of neighbors
    dbg(GENERAL_CHANNEL, "beacon response received from %i\n", msg->src);
  }
}