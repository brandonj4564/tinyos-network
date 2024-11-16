#include "../../includes/socket.h"

configuration TransportC { provides interface Transport; }

implementation {
  components TransportP;
  Transport = TransportP.Transport;

  components MainC;
  components InternetProtocolC;
  components new TimerMilliC() as CloseClient;
  components new TimerMilliC() as WaitClose;
  components RandomC as Random;
  components new ListC(socket_t, MAX_NUM_OF_SOCKETS) as ClosingQueue;

  TransportP->MainC.Boot;
  TransportP.InternetProtocol->InternetProtocolC;
  TransportP.CloseClient->CloseClient;
  TransportP.WaitClose->WaitClose;
  TransportP.Random->Random;
  TransportP.ClosingQueue->ClosingQueue;
}