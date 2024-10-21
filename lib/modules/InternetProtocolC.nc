configuration InternetProtocolC { provides interface InternetProtocol; }

implementation {
  components InternetProtocolP;
  InternetProtocol = InternetProtocolP.InternetProtocol;

  components MainC;
  components new SimpleSendC(AM_PACK);
  components LinkStateC;
  components new HashmapC(uint16_t, 20) as Cache;
  components new TimerMilliC() as CacheReset;

  InternetProtocolP->MainC.Boot;
  InternetProtocolP.SimpleSend->SimpleSendC;
  InternetProtocolP.LinkState->LinkStateC;
  InternetProtocolP.Cache->Cache;
  InternetProtocolP.CacheReset->CacheReset;
}