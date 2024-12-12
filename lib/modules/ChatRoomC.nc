#include "../../includes/packet.h"
#include "../../includes/socket.h"

configuration ChatRoomC { provides interface ChatRoom; }

implementation {
  components ChatRoomP;
  ChatRoom = ChatRoomP.ChatRoom;

  components MainC;
  components TransportC;
  components new TimerMilliC() as InitListenerSocket;
  components new ListC(socket_t, 15) as MessageIdQueue;
  components new HashmapC(socket_t, 8) as CorrespondingSocket;

  ChatRoomP->MainC.Boot;
  ChatRoomP.Transport->TransportC;
  ChatRoomP.InitListenerSocket->InitListenerSocket;
  ChatRoomP.MessageIdQueue->MessageIdQueue;
  ChatRoomP.CorrespondingSocket->CorrespondingSocket;
}