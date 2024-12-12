#include "../../includes/packet.h"
#include "../../includes/socket.h"

module ChatRoomP {
  provides interface ChatRoom;

  uses interface Boot;
  uses interface Transport;
  uses interface Timer<TMilli> as InitListenerSocket;
  uses interface List<socket_t> as MessageIdQueue;
  uses interface Hashmap<socket_t> as CorrespondingSocket;
}

implementation {
  enum messageType {
    HELLO = 0,
    MESSAGE = 1,
    WHISPER = 2,
    LIST = 3,
    UNKNOWN = 4
  };

  void printMessageType(char *str, uint8_t flag) {
    switch (flag) {
    case HELLO:
      dbg(CHAT_CHANNEL, "%sHELLO\n", str);
      return;
    case MESSAGE:
      dbg(CHAT_CHANNEL, "%sMESSAGE\n", str);
      return;
    case WHISPER:
      dbg(CHAT_CHANNEL, "%sWHISPER\n", str);
      return;
    case LIST:
      dbg(CHAT_CHANNEL, "%sLIST\n", str);
      return;
    }
  }

  typedef struct chat_connection_t {
    bool bound;
    socket_t fd;

    char username[50];
    uint8_t usernameLen;
  } chat_connection_t;

  // This list is only used by node 1, the server
  // It is 1 less than max num because one of the sockets must be the listener
  chat_connection_t connectionList[MAX_NUM_OF_SOCKETS - 1];

  // This is the socket used by the client to connect to the server
  socket_t clientSocket;
  bool clientConnected = FALSE;

  // I'll limit username length to 50 characters. This shouldn't really matter
  char username[50];
  uint8_t usernameLen = 0;

  // Is the handleMessage task ongoing?
  bool handlingMessage = FALSE;

  uint8_t messageBuffSize = 250;
  uint8_t messageDataBuffer[MAX_NUM_OF_SOCKETS][250];
  uint8_t messageBufferIndex[MAX_NUM_OF_SOCKETS];

  event void Boot.booted() {
    uint8_t i;
    // Initialize a listener socket on port 41 at node id 1
    if (TOS_NODE_ID == 1) {
      call InitListenerSocket.startOneShot(500);
    }

    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      messageBufferIndex[i] = 0;
    }
  }

  event void InitListenerSocket.fired() {
    // This is necessary because if we initialize the socket in Boot.booted(),
    // the socket list initialization in Transport occurs AFTERWARDS and
    // OVERWRITES THAT SOCKET... so we need to wait a little

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

  bool isEndSymbol(char *begin) {
    if (begin[0] == '\0') {
      return FALSE;
    }

    if (begin[0] != '\\') {
      return FALSE;
    }

    if (begin[1] == '\0') {
      return FALSE;
    }

    if (begin[1] != 'r') {
      return FALSE;
    }

    if (begin[2] == '\0') {
      return FALSE;
    }

    if (begin[2] != '\\') {
      return FALSE;
    }

    if (begin[3] == '\0') {
      return FALSE;
    }

    if (begin[3] != 'n') {
      return FALSE;
    }

    return TRUE;
  }

  uint8_t stringToInt(char *str, uint8_t len) {
    uint8_t result = 0;
    uint8_t i;

    // Process each character in the string
    for (i = 0; i < len; i++) {
      // Ensure the character is a digit
      if (str[i] >= '0' && str[i] <= '9') {
        result = result * 10 + (str[i] - '0'); // Shift left and add the digit
      } else {
        // Handle invalid input (non-digit character)
        return 0; // Return error code
      }
    }

    return result;
  }

  void handleHello(char *contents) {
    // This will initiate a TCP connection with the server at node 1, port 41
    uint8_t i = 0;

    char *port;
    uint8_t portLen = 0;

    socket_addr_t clientAddr;
    socket_addr_t listenerAddr;
    socket_addr_t serverAddr;
    error_t outcome;
    socket_t fd;

    // Get the username from the message
    while (contents[i] != ' ') {
      if (contents[i] == '\0' || isEndSymbol(&(contents[i]))) {
        dbg(CHAT_CHANNEL, "ERROR: Hello command lacks a username!\n");
        return;
      }
      username[i] = contents[i];
      usernameLen++;
      i++;
    }

    port = &(contents[i + 1]);

    // Extract the port number
    while (contents[i + 1] != '\0' && !isEndSymbol(&(contents[i + 1]))) {
      if (contents[i + 1] == ' ') {
        dbg(CHAT_CHANNEL, "ERROR: Extra space after port number!\n");
        return;
      }

      portLen++;
      i++;
    }

    if (portLen == 0) {
      dbg(CHAT_CHANNEL, "ERROR: Hello command lacks a port!\n");
      return;
    }

    // dbg(CHAT_CHANNEL, "Username len: %u\n", usernameLen);
    // dbg(CHAT_CHANNEL, "Port: %u\n", stringToInt(port, portLen));

    // Time to initiate a TCP connection
    clientSocket = call Transport.socket();
    clientAddr.port = stringToInt(port, portLen);
    clientAddr.addr = TOS_NODE_ID;

    // Hard coded according to the values specified in the document
    serverAddr.port = 41;
    serverAddr.addr = 1;

    outcome = call Transport.bind(clientSocket, &clientAddr);
    if (outcome == FAIL) {
      dbg(CHAT_CHANNEL, "ChatRoom binding client socket failed...\n");
      return;
    }

    outcome = call Transport.connect(clientSocket, &serverAddr);
    if (outcome == FAIL) {
      dbg(CHAT_CHANNEL, "ChatRoom connecting to server failed...\n");
      return;
    }

    // Need to make two sockets because I did not make TCP bidirectional
    // (oopsie)
    fd = call Transport.socket();
    listenerAddr.port = 41;
    listenerAddr.addr = TOS_NODE_ID;

    outcome = call Transport.bind(fd, &listenerAddr);
    if (outcome == FAIL) {
      dbg(CHAT_CHANNEL, "ChatRoom binding client listener socket failed...\n");
      return;
    }

    outcome = call Transport.listen(fd);
    if (outcome == FAIL) {
      dbg(CHAT_CHANNEL, "ChatRoom failed to init client listener socket...\n");
      return;
    }
  }

  uint8_t getMessageType(char *msg) {
    uint8_t commandType = UNKNOWN;
    uint8_t i;

    bool possiblyHello = TRUE;
    bool possiblyMsg = TRUE;
    bool possiblyWhisper = TRUE;
    bool possiblyList = TRUE;

    char *helloCommand = "hello";
    char *messageCommand = "msg";
    char *whisperCommand = "whisper";
    char *listCommand = "list";

    while (msg[i] != '\0') {

      if (possiblyHello) {
        if (msg[i] == helloCommand[i]) {
          if (msg[i] == 'o' && msg[i + 1] == ' ') {
            // This is the final letter, so it is confirmed to be hello
            commandType = HELLO;
            break;
          }
        } else {
          possiblyHello = FALSE;
        }
      }

      if (possiblyMsg) {
        if (msg[i] == messageCommand[i]) {
          if (msg[i] == 'g' && msg[i + 1] == ' ') {
            // This is the final letter, so it is confirmed to be hello
            commandType = MESSAGE;
            break;
          }
        } else {
          possiblyMsg = FALSE;
        }
      }

      if (possiblyWhisper) {
        if (msg[i] == whisperCommand[i]) {
          if (msg[i] == 'r' && msg[i + 1] == ' ') {
            // This is the final letter, so it is confirmed to be hello
            commandType = WHISPER;
            break;
          }
        } else {
          possiblyWhisper = FALSE;
        }
      }

      if (possiblyList) {
        if (msg[i] == listCommand[i]) {
          if (msg[i] == 't' && msg[i + 1] == ' ') {
            // This is the final letter, so it is confirmed to be hello
            commandType = LIST;
            break;
          }
        } else {
          possiblyList = FALSE;
        }
      }

      i++;
    }

    return commandType;
  }

  command void ChatRoom.sendMessage(char *msg) {
    uint8_t commandType = getMessageType(msg);

    // Contents is the stuff in the message after the name of the message
    // Ex: hello acerpa. Content is 'acerpa'
    char *contents;

    dbg(CHAT_CHANNEL, "Sending message: %s\n", msg);

    if (commandType == UNKNOWN) {
      dbg(CHAT_CHANNEL, "Unknown command!\n");
      return;
    }

    if (commandType == HELLO) {

      dbg(CHAT_CHANNEL, "Command type: HELLO\n");

      // contents begin at index 6 because indices 0-5 are 'hello ', which is
      // not useful anymore
      contents = &(msg[6]);
      dbg(CHAT_CHANNEL, "Contents: %s\n", contents);

      handleHello(contents);
    } else if (commandType == MESSAGE) {

      dbg(CHAT_CHANNEL, "Command type: MSG\n");
    } else if (commandType == WHISPER) {

      dbg(CHAT_CHANNEL, "Command type: WHISPER\n");
    } else if (commandType == LIST) {

      dbg(CHAT_CHANNEL, "Command type: LIST\n");
    }

    return;
  }

  // I just realized a MASSIVE flaw with my design philosophy from project 3
  // but at this point it's too late to fix Basically, since the connection
  // received event is broadcast to every module that uses the Transport
  // interface, every module can accept every other module's TCP connections
  event void Transport.newConnectionReceived(socket_t fd) {
    if (TOS_NODE_ID == 1) {
      // Accept the connection and add it to the list
      uint8_t i;
      bool canAccept = FALSE;

      dbg(CHAT_CHANNEL, "New connection from client received!\n");

      for (i = 0; i < MAX_NUM_OF_SOCKETS - 1; i++) {
        if (!connectionList[i].bound) {
          connectionList[i].bound = TRUE;
          connectionList[i].fd = fd;

          canAccept = TRUE;
          break;
        }
      }

      if (canAccept) {
        call Transport.accept(fd);
      } else {
        dbg(CHAT_CHANNEL, "No more connections can be accepted!\n");
      }
    } else {
      // This is the client accepting the connection from the chat server
      dbg(CHAT_CHANNEL, "New connection from server received!\n");
      call Transport.accept(fd);
    }
  }

  event void Transport.connectionSuccess(socket_t fd) {
    if (TOS_NODE_ID == 1) {

    } else {
      // Send the username
      uint8_t i;
      char message[6 + usernameLen + 4];
      message[0] = 'h';
      message[1] = 'e';
      message[2] = 'l';
      message[3] = 'l';
      message[4] = 'o';
      message[5] = ' ';

      for (i = 0; i < usernameLen; i++) {
        message[i + 6] = username[i];
      }

      message[usernameLen + 6 + 0] = '\\';
      message[usernameLen + 6 + 1] = 'r';
      message[usernameLen + 6 + 2] = '\\';
      message[usernameLen + 6 + 3] = 'n';
      message[usernameLen + 6 + 4] = '\0';

      clientConnected = TRUE;

      dbg(CHAT_CHANNEL, "message to server: %s\n", message);

      call Transport.write(fd, (uint8_t *)message, 6 + usernameLen + 4);
    }
  }

  void handleMessageServer(char *msg, uint8_t len, socket_t fd) {
    uint8_t i = 0;
    uint8_t commandType = getMessageType(msg);

    if (commandType == UNKNOWN) {
      dbg(CHAT_CHANNEL, "Unknown command received!\n");
      return;
    }

    if (commandType == HELLO) {
      char *contents = &(msg[6]);
      socket_addr_t source;
      socket_addr_t dest;
      error_t outcome;

      socket_t newSocket = call Transport.socket();
      source.port = 41;
      source.addr = TOS_NODE_ID;

      // Hard coded according to the values specified in the document
      dest.port = 41;
      dest.addr = (call Transport.getSocketAddr(fd))->addr;

      outcome = call Transport.bind(newSocket, &source);
      if (outcome == FAIL) {
        dbg(CHAT_CHANNEL, "ChatRoom binding server socket failed...\n");
        return;
      }

      outcome = call Transport.connect(newSocket, &dest);
      if (outcome == FAIL) {
        dbg(CHAT_CHANNEL, "ChatRoom connecting to client failed...\n");
        return;
      }

      // Add this to a hashmap so the server knows which socket to use to reply
      call CorrespondingSocket.insert(fd, newSocket);

      i = 0;
      while (!isEndSymbol(&(contents[i]))) {
        (connectionList[fd].username)[i] = contents[i];
        i++;
      }
      (connectionList[fd].username)[i] = '\0';
      connectionList[fd].usernameLen = i;

      //   dbg(CHAT_CHANNEL, "username: %s\n", connectionList[fd].username);
      //   dbg(CHAT_CHANNEL, "usernameLen: %u\n",
      //   connectionList[fd].usernameLen);

    } else if (commandType == MESSAGE) {

    } else if (commandType == WHISPER) {

    } else if (commandType == LIST) {
    }
  }

  void handleMessageClient(char *msg, uint8_t len, socket_t fd) {
    //
  }

  task void handleMessage() {
    socket_t fd = call MessageIdQueue.popfront();
    char fullMessage[messageBufferIndex[fd]];
    uint8_t i;

    dbg(CHAT_CHANNEL, "Begin handing message.\n");

    for (i = 0; i < messageBufferIndex[fd]; i++) {
      fullMessage[i] = messageDataBuffer[fd][i];
    }
    fullMessage[messageBufferIndex[fd]] = '\0';

    dbg(CHAT_CHANNEL, "Message: %s\n", fullMessage);

    if (TOS_NODE_ID == 1) {
      handleMessageServer(fullMessage, messageBufferIndex[fd], fd);
    } else {
      handleMessageClient(fullMessage, messageBufferIndex[fd], fd);
    }

    // Reset the index for the corresponding message buffer so that another
    // message can be written in there
    messageBufferIndex[fd] = 0;

    if (!(call MessageIdQueue.isEmpty())) {
      post handleMessage();
    } else {
      handlingMessage = FALSE;
    }
  }

  event void Transport.dataAvailable(socket_t fd) {
    if (TOS_NODE_ID == 1) {
      // Server receives data from clients
      uint8_t lengthRead;
      dbg(CHAT_CHANNEL, "Message received!\n");

      lengthRead = call Transport.read(
          fd, &messageDataBuffer[fd][messageBufferIndex[fd]],
          messageBuffSize - messageBufferIndex[fd]);
      messageBufferIndex[fd] += lengthRead;

      // dbg(CHAT_CHANNEL, "Message length: %u\n", lengthRead);
      // dbg(CHAT_CHANNEL, "Message buffer index: %u\n",
      // messageBufferIndex[fd]);

      if (messageBufferIndex[fd] >= 4) {
        char *fourCharsBeforeEnd =
            (char *)(&(messageDataBuffer[fd][messageBufferIndex[fd] - 4]));

        if (isEndSymbol(fourCharsBeforeEnd)) {
          // Basically, this is the end of the message and it has fully arrived
          // dbg(CHAT_CHANNEL, "End of message!\n");

          call MessageIdQueue.pushback(fd);

          if (!handlingMessage) {
            post handleMessage();
          }
        }
      }
    } else {
      // client receives data from the server
      dbg(CHAT_CHANNEL, "Message received at client from server!\n");
    }
  }

  event void Transport.bufferFreed(socket_t fd) {}

  event void Transport.alertClose(socket_t fd) {}
}