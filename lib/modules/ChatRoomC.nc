#include "../../includes/packet.h"

configuration ChatRoomC { provides interface ChatRoom; }

implementation {
  components ChatRoomP;
  ChatRoom = ChatRoomP.ChatRoom;

  components MainC;
  components TransportC;
  components new TimerMilliC() as InitListenerSocket;

  ChatRoomP->MainC.Boot;
  ChatRoomP.Transport->TransportC;
  ChatRoomP.InitListenerSocket->InitListenerSocket;
}