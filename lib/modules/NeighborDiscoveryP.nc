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

  //Hashmap
  uses interface Hashmap<uint16_t> as transmissions;

  uses interface Hashmap<uint32_t*> as neighborList;

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

  // The number of beacons sent
  uint16_t beaconsSent = 1;
  uint16_t sequenceNum = 0;

  void forgetNeighborResponse() {
    uint32_t* nodeKeys;
    nodeKeys = call transmissions.getKeys();
    uint16_t i;
    for (i = 0; i < call transmissions.size(); i++){
      uint32_t* transArray = call transmissions.get(nodeKeys[i]);
      transArray[sequenceNum % 5] = 0;

    }
  }

  event void beaconTimer.fired() {
    pack beacon;
    uint8_t payload[1] = {0}; // Beacon packets don't really need a payload

    makePack(&beacon, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, 1,
             payload, sizeof(payload));

    // Send the beacon
    call SimpleSend.send(beacon, AM_BROADCAST_ADDR);  

    //depending on sequence number, make all arrays in that (sequence % 5) zero 
    forgetNeighborResponse();

    sequenceNum++;
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

    /*if (src not in hashmap){
        initialize array
        add src and array to hasmap
      } else {
        access array corresponding to src
        add 1 to array position depending on (sequence % 5)

      }

    */

    if(call transmissions.contain(src)){
        uint32_t* transArray = call transmissions.get(src);
        transArray[sequenceNum % 5] = 1;
    } else{
      uint32_t transmit[5] = {0,0,0,0,0};
      transmit[sequence % 5] = 1; 
      call transmissions.insert(src, transmit);
    }

  }

  void areNeighborsWorthy(){ 
    //Threshold = 60%
    float threshold = 0.6;

    float stat = 0;

    //Go to each list and get an array from there.
    //..............................................................
      uint32_t * nodeKeys = call transmissions.getKeys();
      int valueNumSumOfTum = 0;

      for (uint16_t i = 0; i < call transmissions.size(); i++){
        uint32_t* transArray = call transmissions.get(nodeKeys[i]);
        for(uint16_t j = 0; j < 5; j++){
          valueNumSumOfTum += transArray[j];
        }

        float denominator = 5;
        if(beaconsSent < 5){
          denominator = beaconsSent;
        } 
        float numRecieved = valueNumSumOfTum;
        
        if(numRecieved/denominator >= threshold){
          if(!(call neighborList.contain(nodeKeys[i]))){
            call neighborList.insert(nodeKeys[i], numRecieved/denominator);
          } else{
            call neighborList.remove(nodeKeys[i]);
            call neighborList.insert(nodeKeys[i], numRecieved/denominator);
          }
        } else {
          if(call neighborList.contain(nodeKeys[i])){
            call neighborList.remove(nodeKeys[i]);
          }
        }

        valueNumSumOfTum = 0;
      }
    //..............................................................
    
  }

  command uint32_t * NeighborDiscovery.getNeighbors(){
    return call neighborList.getKeys();
  }

  command uint16_t NeighborDiscovery.getNumNeighbors(){
    return call neighborList.size();
  }
  
  
}