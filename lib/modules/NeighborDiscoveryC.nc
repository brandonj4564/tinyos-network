configuration NeighborDiscoveryC { provides interface NeighborDiscovery; }

implementation {
  components NeighborDiscoveryP;
  NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

  // Timer instantiation
  components new TimerMilliC() as beaconTimer;
  NeighborDiscoveryP.beaconTimer->beaconTimer;

  components new SimpleSendC(AM_PACK);
  NeighborDiscoveryP.SimpleSend->SimpleSendC;

  components new ListC(uint16_t, 50);
  FloodingP.Transmit1->HashmapC;
  components new ListC(uint16_t, 50);
  FloodingP.Transmit2->HashmapC;
  components new ListC(uint16_t, 50);
  FloodingP.Transmit3->HashmapC;
  components new ListC(uint16_t, 50);
  FloodingP.Transmit4->HashmapC;
  components new ListC(uint16_t, 50);
  FloodingP.Transmit5->HashmapC;

  components new HashmapC(uint16_t, 50);
  FloodingP.numAppearances->HashmapC;
}