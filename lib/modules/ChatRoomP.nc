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
  uint8_t maxNumConnections = (MAX_NUM_OF_SOCKETS) / 2 - 1;
  chat_connection_t connectionList[(MAX_NUM_OF_SOCKETS) / 2 - 1];

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

  void printAllConnections() {
    uint8_t i;
    for (i = 0; i < maxNumConnections; i++) {
      chat_connection_t *currConn = &connectionList[i];

      if (currConn->bound) {
        dbg(CHAT_CHANNEL, "--------------- USER ---------------\n");
        dbg(CHAT_CHANNEL, "index: %u\n", i);
        dbg(CHAT_CHANNEL, "username: %s\n", currConn->username);
        dbg(CHAT_CHANNEL, "receive socket: %u\n", currConn->fd);
        dbg(CHAT_CHANNEL, "send socket: %u\n",
            call CorrespondingSocket.get(currConn->fd));
      }
    }
  }

  event void Boot.booted() {
    uint8_t i;
    // Initialize a listener socket on port 41 at node id 1
    if (TOS_NODE_ID == 1) {
      call InitListenerSocket.startOneShot(500);
    }

    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      messageBufferIndex[i] = 0;

      if (i < maxNumConnections) {
        connectionList[i].bound = FALSE;
      }
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

    for (i = 0; i < maxNumConnections; i++) {
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
    char *listCommand = "listusr";

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
          if (msg[i] == 'r' && isEndSymbol(msg + i + 1)) {
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
    uint8_t i = 0;

    // Contents is the stuff in the message after the name of the message
    // Ex: hello acerpa. Content is 'acerpa'
    char *contents;

    dbg(CHAT_CHANNEL, "Sending message: %s\n", msg);

    if (commandType == UNKNOWN) {
      dbg(CHAT_CHANNEL, "Unknown command!\n");
      return;
    }

    if (commandType == HELLO) {
      // This will initiate a TCP connection with the server at node 1, port
      // 41

      char *port;
      uint8_t portLen = 0;

      socket_addr_t clientAddr;
      socket_addr_t listenerAddr;
      socket_addr_t serverAddr;
      error_t outcome;
      socket_t fd;

      // dbg(CHAT_CHANNEL, "Command type: HELLO\n");

      if (clientConnected) {
        // client already connected, don't do it again
        dbg(CHAT_CHANNEL, "ERROR: Client already connected!\n");
        return;
      }

      // contents begin at index 6 because indices 0-5 are 'hello ', which is
      // not useful anymore
      contents = &(msg[6]);

      // dbg(CHAT_CHANNEL, "Contents: %s\n", contents);

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
        dbg(CHAT_CHANNEL,
            "ChatRoom binding client listener socket failed...\n");
        return;
      }

      outcome = call Transport.listen(fd);
      if (outcome == FAIL) {
        dbg(CHAT_CHANNEL,
            "ChatRoom failed to init client listener socket...\n");
        return;
      }

    } else {
      // Only 'hello' commands need special functionality on the client side
      // All other commands only require special functions on the server side

      if (!clientConnected) {
        // Can't send other commands until the hello command has been sent!
        dbg(CHAT_CHANNEL, "Must send 'hello' command first!\n");
        return;
      }

      i = 0;
      while (msg[i] != '\0') {
        i++;
      }
      //   dbg(CHAT_CHANNEL, "Message len: %u\n", i);

      call Transport.write(clientSocket, (uint8_t *)msg, i);
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

      // dbg(CHAT_CHANNEL, "New connection from client received!\n");

      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound && connectionList[i].fd == fd) {
          // Checks if this user is already connected
          dbg(CHAT_CHANNEL, "You are already connected!\n");

          return;
        }
      }

      for (i = 0; i < maxNumConnections; i++) {
        if (!connectionList[i].bound) {
          // dbg(CHAT_CHANNEL, "Binding connection index %u\n", i);
          connectionList[i].bound = TRUE;

          canAccept = TRUE;
          break;
        }
      }

      if (canAccept) {
        connectionList[i].fd = call Transport.accept(fd);
      } else {
        dbg(CHAT_CHANNEL, "No more connections can be accepted!\n");
      }
    } else {
      // This is the client accepting the connection from the chat server
      error_t outcome;
      // dbg(CHAT_CHANNEL, "New connection from server received!\n");
      outcome = call Transport.accept(fd);

      if (outcome == FAIL) {
        dbg(CHAT_CHANNEL, "Failed to accept connection from server!\n");
      }
    }
  }

  event void Transport.connectionSuccess(socket_t fd) {
    if (TOS_NODE_ID == 1) {
      // Server connection success
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

      // dbg(CHAT_CHANNEL, "message to server: %s\n", message);

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
      uint8_t connection = 0;
      socket_addr_t source;
      socket_addr_t dest;
      error_t outcome;

      socket_t newSocket = call Transport.socket();
      source.port = 41;
      source.addr = TOS_NODE_ID;

      // Hard coded according to the values specified in the document
      dest.port = 41;
      dest.addr = (call Transport.getSocketAddr(fd))->addr;

      // dbg(CHAT_CHANNEL, "Message: %s\n", msg);

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

      // Get the connection
      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound && connectionList[i].fd == fd) {
          connection = i;
        }
      }

      i = 0;
      while (!isEndSymbol(&(contents[i]))) {
        (connectionList[connection].username)[i] = contents[i];
        i++;
      }
      (connectionList[connection].username)[i] = '\0';
      connectionList[connection].usernameLen = i;

      // printAllConnections();

      // dbg(CHAT_CHANNEL, "username: %s\n",
      // connectionList[connection].username);
      // dbg(CHAT_CHANNEL, "usernameLen:  %u\n",
      //     connectionList[connection].usernameLen);

    } else if (commandType == MESSAGE) {
      chat_connection_t *currConn;
      bool foundConn = FALSE;

      // Limit the potential message size to the max size of the buffer
      char messageToSend[messageBuffSize];
      uint8_t currPosition = 0;
      uint8_t messageLen = 0;

      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound && connectionList[i].fd == fd) {
          currConn = &(connectionList[i]);
          foundConn = TRUE;
        }
      }

      if (!foundConn) {
        dbg(CHAT_CHANNEL, "No corresponding socket found for that message!\n");
        return;
      }

      // Generate the message to send
      // username: message
      for (currPosition = 0; currPosition < currConn->usernameLen;
           currPosition++) {
        messageToSend[currPosition] = (currConn->username)[currPosition];
      }

      // Add the semicolon and space
      messageToSend[currPosition] = ':';
      currPosition = currPosition + 1;
      messageToSend[currPosition] = ' ';
      currPosition = currPosition + 1;

      // Set i to 4 to skip the 'msg' part of 'msg MESSAGE'
      for (i = 4; i < len; i++) {
        messageToSend[currPosition + i - 4] = msg[i];
      }
      messageLen = currPosition + len - 4;
      messageToSend[messageLen] = '\0';

      //   dbg(CHAT_CHANNEL, "message in total: %s\n", messageToSend);
      //   dbg(CHAT_CHANNEL, "message in total len: %u\n", messageLen);

      // Now that we have the message to send, time to loop through all chat
      // connections and send the message
      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound) {

          // Only send if you can find the corresponding write socket
          if (call CorrespondingSocket.contains(connectionList[i].fd)) {
            socket_t writeSocket =
                call CorrespondingSocket.get(connectionList[i].fd);

            error_t outcome;
            // dbg(CHAT_CHANNEL, "Broadcasting to socket %u\n", writeSocket);

            outcome = call Transport.write(
                writeSocket, (uint8_t *)messageToSend, messageLen);

            if (outcome == FAIL) {
              dbg(CHAT_CHANNEL, "Failed to broadcast to %u\n", writeSocket);
            }
          }
        }
      }

    } else if (commandType == WHISPER) {
      // basically just copy everything from the MESSAGE part above except only
      // send to one node
      chat_connection_t *currConn;
      bool foundConn = FALSE;

      char recipientUser[50];
      uint8_t recipientUserLen = 0;

      // Limit the potential message size to the max size of the buffer
      char messageToSend[messageBuffSize];
      uint8_t currPosition = 0;
      uint8_t messageLen = 0;

      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound && connectionList[i].fd == fd) {
          currConn = &(connectionList[i]);
          foundConn = TRUE;
        }
      }

      if (!foundConn) {
        dbg(CHAT_CHANNEL, "No corresponding socket found for that message!\n");
        return;
      }

      // Extract the username from the whisper command
      // 'whisper ' is 8 characters, so skip that
      i = 8;
      while (msg[i] != ' ') {
        if (isEndSymbol(msg + i)) {
          dbg(CHAT_CHANNEL,
              "A whisper command must contain a username and a message!\n");
          return;
        }

        recipientUser[i - 8] = msg[i];
        i++;
        recipientUserLen++;
      }
      recipientUser[recipientUserLen] = '\0';

      // Generate the message to send
      // username: message
      for (currPosition = 0; currPosition < currConn->usernameLen;
           currPosition++) {
        messageToSend[currPosition] = (currConn->username)[currPosition];
      }

      // Add the semicolon and space
      messageToSend[currPosition] = ':';
      currPosition = currPosition + 1;
      messageToSend[currPosition] = ' ';
      currPosition = currPosition + 1;

      // Set i to 9 to skip the 'whisper ' part and the extra space ' ' between
      // the username and actual message
      // 'whisper brand Hello!'
      for (i = 9; i < len; i++) {
        messageToSend[currPosition + i - 9] = msg[i + recipientUserLen];
      }
      messageLen = currPosition + len - 9 - recipientUserLen;
      messageToSend[messageLen] = '\0';

      // dbg(CHAT_CHANNEL, "username in total: %s\n", recipientUser);
      // dbg(CHAT_CHANNEL, "username in total len: %u\n", recipientUserLen);

      // dbg(CHAT_CHANNEL, "message in total: %s\n", messageToSend);
      // dbg(CHAT_CHANNEL, "message in total len: %u\n", messageLen);

      //  Time to locate the chat connection with the corresponding username (if
      //  it exists) and send the message
      for (i = 0; i < maxNumConnections; i++) {
        if (connectionList[i].bound) {
          uint8_t j = 0;
          chat_connection_t *thisConnection = &connectionList[i];
          bool usernamesEqual = FALSE;

          // Compare usernames
          if (thisConnection->usernameLen == recipientUserLen) {
            usernamesEqual = TRUE;
            for (j = 0; j < recipientUserLen; j++) {
              if ((thisConnection->username)[j] != recipientUser[j]) {
                usernamesEqual = FALSE;
              }
            }
          }

          // Only send if you can find the corresponding write socket
          if (usernamesEqual &&
              call CorrespondingSocket.contains(thisConnection->fd)) {
            socket_t writeSocket =
                call CorrespondingSocket.get(thisConnection->fd);

            call Transport.write(writeSocket, (uint8_t *)messageToSend,
                                 messageLen);

            break;
          }
        }
      }

    } else if (commandType == LIST) {
      // Need to return a list of usernames
      char messageToSend[messageBuffSize];
      uint8_t currPosition = 0;

      // Used to stop adding a comma at the start of the string
      bool firstName = TRUE;

      socket_t writeSocket;

      //   dbg(CHAT_CHANNEL, "LIST command received!\n");

      // Okay look, I *know* there's probably a better way of doing this but I
      // don't feel like looking it up right now
      messageToSend[currPosition] = 'u';
      currPosition++;
      messageToSend[currPosition] = 's';
      currPosition++;
      messageToSend[currPosition] = 'e';
      currPosition++;
      messageToSend[currPosition] = 'r';
      currPosition++;
      messageToSend[currPosition] = 's';
      currPosition++;
      messageToSend[currPosition] = ':';
      currPosition++;
      messageToSend[currPosition] = ' ';
      currPosition++;

      for (i = 0; i < maxNumConnections; i++) {
        // loop through all connections and get all the usernames
        if (connectionList[i].bound) {
          chat_connection_t *currConn = &connectionList[i];
          char *user = currConn->username;
          uint8_t length = currConn->usernameLen;
          uint8_t j;

          if (firstName) {
            // start adding commas from now on
            firstName = FALSE;
          } else {
            messageToSend[currPosition] = ',';
            currPosition++;
            messageToSend[currPosition] = ' ';
            currPosition++;
          }

          // copy each username into the message
          for (j = 0; j < length; j++) {
            messageToSend[currPosition] = user[j];
            currPosition++;
          }
        }
      }

      messageToSend[currPosition] = '\\';
      currPosition++;
      messageToSend[currPosition] = 'r';
      currPosition++;
      messageToSend[currPosition] = '\\';
      currPosition++;
      messageToSend[currPosition] = 'n';
      currPosition++;
      messageToSend[currPosition] = '\0';

      //   dbg(CHAT_CHANNEL, "%s\n", messageToSend);

      if (!(call CorrespondingSocket.contains(fd))) {
        dbg(CHAT_CHANNEL, "No corresponding write socket for %u\n", fd);
        return;
      }
      writeSocket = call CorrespondingSocket.get(fd);

      call Transport.write(writeSocket, (uint8_t *)messageToSend, currPosition);
    }
  }

  task void handleMessage() {
    socket_t fd = call MessageIdQueue.popfront();
    char fullMessage[messageBufferIndex[fd]];
    uint8_t i;

    // dbg(CHAT_CHANNEL, "Begin handling message.\n");

    for (i = 0; i < messageBufferIndex[fd]; i++) {
      fullMessage[i] = messageDataBuffer[fd][i];
    }
    fullMessage[messageBufferIndex[fd]] = '\0';

    if (TOS_NODE_ID == 1) {
      //   dbg(CHAT_CHANNEL, "Message at server: %s\n", fullMessage);
      handleMessageServer(fullMessage, messageBufferIndex[fd], fd);
    } else {
      // The client pretty much only needs to display the message

      // This gets rid of the \r\n stuff at the end
      i = 0;
      while (fullMessage[i] != '\0') {
        i++;
      }
      fullMessage[i - 4] = '\0';

      dbg(CHAT_CHANNEL, "%s\n", fullMessage);
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
    // Server receives data from clients
    uint8_t lengthRead;
    // dbg(CHAT_CHANNEL, "Message received!\n");

    lengthRead =
        call Transport.read(fd, &messageDataBuffer[fd][messageBufferIndex[fd]],
                            messageBuffSize - messageBufferIndex[fd]);
    messageBufferIndex[fd] += lengthRead;

    // dbg(CHAT_CHANNEL, "Message length: %u\n", lengthRead);
    // dbg(CHAT_CHANNEL, "Message buffer index: %u\n", messageBufferIndex[fd]);

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
  }

  event void Transport.bufferFreed(socket_t fd) {}

  event void Transport.alertClose(socket_t fd) {}
}