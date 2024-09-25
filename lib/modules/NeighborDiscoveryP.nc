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

  uses interface List<uint16_t> as Transmit1;
  uses interface List<uint16_t> as Transmit2;
  uses interface List<uint16_t> as Transmit3;
  uses interface List<uint16_t> as Transmit4;
  uses interface List<uint16_t> as Transmit5;

  //Hashmap
  use interface Hashmap<uint16_t> as numAppearances;

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

  uint16_t count = 5;
  // The number of beacons sent
  uint16_t beaconsSent = 1;

  event void beaconTimer.fired() {
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, 1,
             payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);  

    if(count > 4){
      count = 0;
      // count++;
    } else{
      count++;
    }
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
    
    uint16_t src = msg->src;

    //clear each hashmap at its respective transmission
    if (count == 0){
      //call hashmap 1
      call Transmit1.pushback(src, 1);

    } else if (count == 1){
      //call Hashmap 2
      call Transmit2.pushback(src, 1);

    } else if (count == 2){
      //call Hashmap 3
      call Transmit3.pushback(src, 1);

    } else if (count == 3){
      //call Hashmap 4
      call Transmit4.pushback(src, 1);

    } else if (count == 4){
      //call Hashmap 5
      call Transmit5.pushback(src, 1);

    }

  }

  void areNeighborsWorthy(){ 
    uint16_t appears = 0;
    //Threshold = 60%
    float threshold = 0.6;

    float stat = 0;

    //Go to each list and get an array from there.


    // uint32_t uniqueArray[100];

    // for(uint16_t i = 0; i < 100; i++){
    // }

    for(uint16_t i = 0; i < 5; i++){

      uint16_t counter = 0;
      while(true){
        uint16_t node;
        // This goes through all of the lists and increments the corresponding entry in
        // numAppearances for each item, basically counting the number of times
        // each node responded to a beacon sent by this current node
        if(i == 0 && counter < call Transmit1.size()){
          // Get a node id from the list of nodes that responded to this beacon
          node = call Transmit1.get(counter);
        }
        else if(i == 1 && counter < call Transmit2.size()){
          node = call Transmit2.get(counter);
        }
        else if(i == 2 && counter < call Transmit3.size()){
          node = call Transmit3.get(counter);
        }
        else if(i == 3 && counter < call Transmit4.size()){
          node = call Transmit4.get(counter);
        }
        else if(i == 4 && counter < call Transmit5.size()){
          node = call Transmit5.get(counter);
        }
        else{
          counter = 0;
          break;
        }

        if(call numAppearances.contains(node)){
          // If numAppearances hashmap contains the node, increase its number of appearances
          uint16_t currentNumAppearances = call numAppearances.get(node);
          currentNumAppearances++;
          call numAppearances.remove(node);
          call numAppearances.insert(node, currentNumAppearances);
        }
        else{
          // Node is not yet in numAppearances so insert it with known one appearance so far
          call numAppearances.insert(node, 1);
        }
        counter++;
      }
    }

    

    float denominator = 5;
    if(beaconsSent < 5){
      denominator = beaconsSent;
    }

    // float neighborStat = stat/denominator;
    if(stat/denominator >= threshold){

    }

  }
}