configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  components InternetProtocolC;
  components new TimerMilliC() as Timer;

  TransportP->MainC.Boot;
  TransportP.InternetProtocol->InternetProtocolC;
  TransportP.Timer->Timer;
}