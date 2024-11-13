configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  components InternetProtocolC;
  components new TimerMilliC() as CloseClient;
  components new TimerMilliC() as WaitClose;
  components RandomC as Random;

  TransportP->MainC.Boot;
  TransportP.InternetProtocol->InternetProtocolC;
  TransportP.CloseClient->CloseClient;
  TransportP.WaitClose->WaitClose;
  TransportP.Random->Random;
}