configuration FloodingC { provides interface Flooding; }

implementation {
  components FloodingP;
  Flooding = FloodingP.Flooding;

  components new SimpleSendC(AM_PACK);
  components new HashmapC(uint16_t, 20); // packet cache size
  components new TimerMilliC() as CacheReset;
  components LinkStateC;

  FloodingP.SimpleSend->SimpleSendC;
  FloodingP.NodeTable->HashmapC;
  FloodingP.CacheReset->CacheReset;
  FloodingP.LinkState->LinkStateC;
}