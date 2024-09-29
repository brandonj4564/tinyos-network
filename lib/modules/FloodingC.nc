configuration FloodingC { provides interface Flooding; }

implementation {
  components FloodingP;
  Flooding = FloodingP.Flooding;

  components new SimpleSendC(AM_PACK);
  components new HashmapC(uint16_t, 20); // packet cache size

  FloodingP.SimpleSend->SimpleSendC;
  FloodingP.NodeTable->HashmapC;

  // Temporary wiring to test NeighborDiscovery, delete after project 1 demo
  components new TimerMilliC() as Timer;
  FloodingP.Timer->Timer;
  components NeighborDiscoveryC;
  FloodingP.NeighborDiscovery->NeighborDiscoveryC;
}