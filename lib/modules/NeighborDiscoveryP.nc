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

module NeighborDiscoveryP {
  // Provides shows the interface we are implementing. See
  // lib/interface/NeighborDiscovery.nc to see what funcitons we need to
  // implement.
  provides interface NeighborDiscovery;
}

implementation {
  // Implements the function
  command void NeighborDiscovery.pass() { dbg(GENERAL_CHANNEL, "hi\n"); }
}