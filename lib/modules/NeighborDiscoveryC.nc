configuration NeighborDiscoveryC { provides interface NeighborDiscovery; }

implementation {
  components NeighborDiscoveryP;
  NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

  // Timer instantiation
  components new TimerMilliC() as beaconTimer;
  NeighborDiscoveryP.beaconTimer->beaconTimer;

  // components NodeC;
  // NodeC.makePack->makePack;

  components new SimpleSendC(AM_PACK);
  NeighborDiscoveryP.SimpleSend->SimpleSendC;
}