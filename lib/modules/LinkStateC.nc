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

  components new HashmapC(uint16_t, 20) as Cache;
  LinkStateP.Cache->Cache;

  components new TimerMilliC() as CacheReset;
  LinkStateP.CacheReset->CacheReset;

  components new TimerMilliC() as InitialDelay;
  LinkStateP.InitialDelay->InitialDelay;
}