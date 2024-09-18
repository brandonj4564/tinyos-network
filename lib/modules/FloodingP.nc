//Needed functions 
//.......Send Message Function
//.......Receive Message Function
//.............Unpack
//..............Needs to get protocol before unpacking to identify flooding method
//.................Recieve.Recive calls this funtion
//...................In this function it checks for destination and decrement TTL in case.
//.....................Then reuse send message function.
//.......Acknowledgment Funtion

module FloodingP {
  // Provides shows the interface we are implementing. See
  // lib/interface/NeighborDiscovery.nc to see what funcitons we need to
  // implement.
  provides interface Flooding;
}

implementation {

  command void Flooding.sendMessage(uint8_t * payload){
    dbg(GENERAL_CHANNEL, "Send Message works!!!!!");
  }

  command void Flooding.recieveMessage(pack * msg){
    dbg(GENERAL_CHANNEL, "Recieve Message works!!!!!");
  }

}