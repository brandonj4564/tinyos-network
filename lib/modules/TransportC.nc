configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  LinkStateP->MainC.Boot;

}