configuration ChatRoomC { provides interface ChatRoom; }

implementation {
  components ChatRoomP;
  ChatRoom = ChatRoomP.ChatRoom;

  components MainC;
  components TransportC;

  ChatRoomP->MainC.Boot;
  ChatRoomP.Transport->TransportC;
}