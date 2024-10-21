configuration InternetProtocolC { provides interface InternetProtocol; }

implementation {
  components InternetProtocolP;
  InternetProtocol = InternetProtocolP.InternetProtocol;

  components new SimpleSendC(AM_PACK);
  components LinkStateC;

  InternetProtocolP.SimpleSend->SimpleSendC;
  InternetProtocolP.LinkState->LinkStateC;
}