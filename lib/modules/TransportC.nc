configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  TransportP->MainC.Boot;
}