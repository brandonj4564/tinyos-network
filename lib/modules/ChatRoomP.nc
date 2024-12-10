#include "../../includes/packet.h"
#include "../../includes/socket.h"

module ChatRoomP {
  provides interface ChatRoom;

  uses interface Boot;
  uses interface Transport;
}

implementation {

  typedef struct chat_connection_t {
    bool bound;
    socket_t fd;
  } chat_connection_t;

  // This list is only used by node 1, the server
  // It is 1 less than max num because one of the sockets must be the listener
  chat_connection_t connectionList[MAX_NUM_OF_SOCKETS - 1];

  event void Boot.booted() {
    // Initialize a listener socket on port 41 at node id 1
    if (TOS_NODE_ID == 1) {
      uint8_t i;
      socket_t fd = call Transport.socket();
      error_t outcome;
      socket_addr_t addr;
      addr.port = 41;
      addr.addr = 1;

      dbg(CHAT_CHANNEL, "Initializing chat listener socket with port 41\n");

      outcome = call Transport.bind(fd, &addr);

      if (outcome == FAIL) {
        dbg(CHAT_CHANNEL, "Something went wrong creating a port...\n");
        return;
      }

      call Transport.listen(fd);
      dbg(CHAT_CHANNEL, "Listener socket set up!\n");

      for (i = 0; i < MAX_NUM_OF_SOCKETS - 1; i++) {
        // initialize connection list
        chat_connection_t *currConn = &connectionList[i];
        currConn->bound = FALSE;
        currConn->fd = 0;
      }
    }
  }

  command void ChatRoom.sendMessage(char *msg) {
    uint8_t i = 0;
    dbg(CHAT_CHANNEL, "Sending message: %s\n", msg);

    while (msg[i] != '\0') {
      i++;
    }
    dbg(CHAT_CHANNEL, "Msg len: %u\n", i);
  }

  event void Transport.newConnectionReceived(socket_t fd) {}

  event void Transport.connectionSuccess(socket_t fd) {}

  event void Transport.dataAvailable(socket_t fd) {}

  event void Transport.bufferFreed(socket_t fd) {}

  event void Transport.alertClose(socket_t fd) {}
}