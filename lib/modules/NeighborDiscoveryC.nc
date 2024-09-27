configuration NeighborDiscoveryC { provides interface NeighborDiscovery; }

implementation {
  components NeighborDiscoveryP;
  NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

  // Timer instantiation
  components new TimerMilliC() as beaconTimer;
  NeighborDiscoveryP.beaconTimer->beaconTimer;

  components new SimpleSendC(AM_PACK);
  NeighborDiscoveryP.SimpleSend->SimpleSendC;

  components new HashmapC(uint16_t, 50);
  NeighborDiscoveryP.neighborList->HashmapC;
  
  components new HashmapC(uint32_t*, 50) as Transmissions;
  NeighborDiscoveryP.transmissions->Transmissions;
}