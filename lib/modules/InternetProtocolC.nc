configuration InternetProtocolC { provides interface InternetProtocol; }

implementation {
  components InternetProtocolP;
  InternetProtocol = InternetProtocolP.InternetProtocol;

  components new SimpleSendC(AM_PACK);
  components LinkStateC;
  components TransportC;

  InternetProtocolP.SimpleSend->SimpleSendC;
  InternetProtocolP.LinkState->LinkStateC;
  InternetProtocolP.Transport->TransportC;
}