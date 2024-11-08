#include "../../includes/socket.h"

configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  components InternetProtocolC;
  components new TimerMilliC() as Timer;
  components new ListC(connection_t, MAX_CONNECTIONS) as PendingConnections;

  TransportP->MainC.Boot;
  TransportP.InternetProtocol->InternetProtocolC;
  TransportP.Timer->Timer;
  TransportP.PendingConnections->PendingConnections;
}