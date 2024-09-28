configuration NeighborDiscoveryC { provides interface NeighborDiscovery; }

implementation {
  components NeighborDiscoveryP;
  NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

  components new TimerMilliC() as beaconTimer;
  components RandomC as Random;
  components new SimpleSendC(AM_PACK);
  // Hashmap has 10 storage
  components new HashmapC(uint16_t, 10);
  components new HashmapC(uint32_t *, 10) as BeaconResponses;

  NeighborDiscoveryP.beaconTimer->beaconTimer;
  NeighborDiscoveryP.Random->Random;
  NeighborDiscoveryP.SimpleSend->SimpleSendC;
  NeighborDiscoveryP.neighborList->HashmapC;
  NeighborDiscoveryP.BeaconResponses->BeaconResponses;
}