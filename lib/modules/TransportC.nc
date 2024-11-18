#include "../../includes/packet.h"
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
  components new ListC(packTCP *, MAX_NUM_OF_SOCKETS * 5) as PacketBuffer;

  TransportP->MainC.Boot;
  TransportP.InternetProtocol->InternetProtocolC;
  TransportP.CloseClient->CloseClient;
  TransportP.WaitClose->WaitClose;
  TransportP.Random->Random;
  TransportP.ClosingQueue->ClosingQueue;
  TransportP.PacketBuffer->PacketBuffer;
}