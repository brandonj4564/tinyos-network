configuration LinkStateC { provides interface LinkState; }

implementation {
  components LinkStateP;
  LinkState = LinkStateP.LinkState;

  components MainC;

  components NeighborDiscoveryC;
  LinkStateP.NeighborDiscovery->NeighborDiscoveryC;

  components FloodingC;
  LinkStateP.Flooding->FloodingC;

  LinkStateP->MainC.Boot;

  components new HashmapC(uint16_t, 20) as cache;
  LinkStateP.cache->cache;

  components new TimerMilliC() as cacheReset;
  LinkStateP.cacheReset->cacheReset;

  components new TimerMilliC() as beaconTimer;
  LinkStateP.beaconTimer->beaconTimer;

  components new HashmapC(uint16_t, 20) as routingTable;
  LinkStateP.routingTable->routingTable;

  components new HashmapC(uint32_t*, 30) as networkTopo;
  LinkStateP.networkTopo->networkTopo;

}