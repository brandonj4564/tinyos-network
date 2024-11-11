#include "../../includes/packet.h"
#include "../../includes/socket.h"

module TransportP {
  provides interface Transport;

  uses interface Boot;
  uses interface InternetProtocol;
  uses interface Timer<TMilli> as Timer;
  uses interface Random;
}

implementation {
  enum {
    // Flags
    SYN = 1,
    ACK = 2,
    SYNACK = 3,
    FIN = 4,
    RST = 5,
    DATA = 6
  };

  typedef nx_struct packTCP {
    nx_uint8_t srcAddr;
    nx_uint8_t srcPort;
    nx_uint8_t destPort;
    nx_uint8_t seq; // initial seq should be randomized based on clock
    nx_uint8_t ack;
    nx_uint8_t flag;
    nx_uint8_t window;
    nx_uint8_t payload[0];
  }
  packTCP;

  void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
               uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
               uint8_t window, uint8_t * payload, uint8_t length) {
    Package->srcAddr = srcAddr;
    Package->srcPort = srcPort;
    Package->destPort = destPort;
    Package->ack = ack;
    Package->seq = seq;
    Package->flag = flag;
    Package->window = window;
    memcpy(Package->payload, payload, length);
  }

  // Null socket, an invalid socket fd
  const uint16_t NULL_SOCKET = MAX_NUM_OF_SOCKETS + 1;

  // A FIFO queue for each potential socket
  connection_t connectionList[MAX_NUM_OF_SOCKETS][MAX_CONNECTIONS];
  uint16_t connectionListIndex[MAX_NUM_OF_SOCKETS];

  // These functions have to be reimplemented because each LISTEN socket needs
  // its own queue
  connection_t popFrontConnection(socket_t fd) {
    connection_t returnVal;
    uint16_t i;
    uint16_t size = connectionListIndex[fd];

    returnVal = connectionList[fd][0];
    if (size > 0) {
      // Move everything to the left.
      for (i = 0; i < size - 1; i++) {
        connectionList[fd][i] = connectionList[fd][i + 1];
      }
      size--;
    }

    return returnVal;
  }

  int getQueueSize(socket_t fd) {
    if (fd >= 0 && fd < MAX_NUM_OF_SOCKETS) {
      return connectionListIndex[fd];
    }
    return NULL_SOCKET;
  }

  connection_t front(socket_t fd) { return connectionList[fd][0]; }

  void pushBack(socket_t fd, connection_t connection) {
    uint16_t ind;
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return;
    }
    ind = connectionListIndex[fd];

    if (ind < MAX_CONNECTIONS) {
      (connectionList[fd][ind]).srcAddr = connection.srcAddr;
      (connectionList[fd][ind]).srcPort = connection.srcPort;
      (connectionList[fd][ind]).destPort = connection.destPort;
      (connectionList[fd][ind]).seq = connection.seq;

      connectionListIndex[fd] = connectionListIndex[fd] + 1;
    }
  }

  socket_store_t socketList[MAX_NUM_OF_SOCKETS];
  // currentSocket is used to index socketList
  uint8_t currentSocket = 0;

  void printSockets() {
    // TODO: make a command that prints out all info for the sockets for testing
    int i;
    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      if (socketList[i].bound) {
        dbg(GENERAL_CHANNEL, "-----NEW SOCKET-----\n");
        dbg(GENERAL_CHANNEL, "Socket fd: %i\n", i);
        dbg(GENERAL_CHANNEL, "Socket state: %i\n", socketList[i].state);
        dbg(GENERAL_CHANNEL, "Socket port: %i\n", socketList[i].src);
        dbg(GENERAL_CHANNEL, "Socket dest addr: %i\n", socketList[i].dest.addr);
        dbg(GENERAL_CHANNEL, "Socket dest port: %i\n", socketList[i].dest.port);

        // Sender portion
        dbg(GENERAL_CHANNEL, "Sender portion\n");
        dbg(GENERAL_CHANNEL, "Socket last written: %i\n",
            socketList[i].lastWritten);
        dbg(GENERAL_CHANNEL, "Socket last ack rcvd: %i\n",
            socketList[i].lastAck);
        dbg(GENERAL_CHANNEL, "Socket last seq sent: %i\n",
            socketList[i].lastSent);

        // Receiver portion
        dbg(GENERAL_CHANNEL, "Receiver portion\n");
        dbg(GENERAL_CHANNEL, "Socket last read: %i\n", socketList[i].lastRead);
        dbg(GENERAL_CHANNEL, "Socket last seq rcvd: %i\n",
            socketList[i].lastRcvd);
        dbg(GENERAL_CHANNEL, "Socket next expected: %i\n",
            socketList[i].nextExpected);

        dbg(GENERAL_CHANNEL, "Socket RTT: %i\n", socketList[i].RTT);
        dbg(GENERAL_CHANNEL, "Socket adv window: %i\n",
            socketList[i].effectiveWindow);
      }
    }
  }

  event void Timer.fired() {
    if (TOS_NODE_ID == 3) {
      socket_t fd;
      socket_addr_t source;
      socket_addr_t dest;

      source.port = 1;
      source.addr = TOS_NODE_ID;
      dest.port = 10;
      dest.addr = 2;

      fd = call Transport.socket();      // gets socket
      call Transport.bind(fd, &source);  // binds port
      call Transport.connect(fd, &dest); // connect to node 2
    }
    printSockets();
  }

  void initTestListeners() {
    socket_t listenerOne;
    socket_t listenerTwo;
    socket_t listenerThree;

    socket_addr_t sourceOne;
    socket_addr_t sourceTwo;
    socket_addr_t sourceThree;

    listenerOne = call Transport.socket();
    sourceOne.port = 10;
    sourceOne.addr = TOS_NODE_ID;
    call Transport.bind(listenerOne, &sourceOne);
    call Transport.listen(listenerOne);

    listenerTwo = call Transport.socket();
    sourceTwo.port = 20;
    sourceTwo.addr = TOS_NODE_ID;
    call Transport.bind(listenerTwo, &sourceTwo);
    call Transport.listen(listenerTwo);

    listenerThree = call Transport.socket();
    sourceThree.port = 30;
    sourceThree.addr = TOS_NODE_ID;
    call Transport.bind(listenerThree, &sourceThree);
    call Transport.listen(listenerThree);
  }

  event void Boot.booted() {
    uint8_t i;

    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      // Initialize all sockets as being free and with default values
      socketList[i].state = CLOSED;
      socketList[i].bound = FALSE;
      socketList[i].flag = 0;
      socketList[i].src = 0;
      socketList[i].dest.port = 0;
      socketList[i].dest.addr = 0;

      // Initialize buffer pointers and counters
      socketList[i].lastWritten = 0;
      socketList[i].lastAck = 0;
      socketList[i].lastSent = 0;
      socketList[i].lastRead = 0;
      socketList[i].lastRcvd = 0;
      socketList[i].nextExpected = 0;

      // Set RTT and window values to 0 or default
      socketList[i].RTT = 0;
      socketList[i].effectiveWindow = SOCKET_BUFFER_SIZE;

      // Optionally initialize buffers to zero
      memset(socketList[i].sendBuff, 0, SOCKET_BUFFER_SIZE);
      memset(socketList[i].rcvdBuff, 0, SOCKET_BUFFER_SIZE);

      connectionListIndex[i] = 0;
    }

    initTestListeners();

    call Timer.startOneShot(30000);
  }

  /**
   * Get a socket if there is one available.
   * @Side Client/Server
   * @return
   *    socket_t - return a socket file descriptor which is a number
   *    associated with a socket. If you are unable to allocated
   *    a socket then return a NULL socket_t.
   */
  command socket_t Transport.socket() {
    // Have a list of available sockets and return one of them i guess
    socket_t sock;
    uint8_t counter = 0; // Prevent infinite loops if no sockets are available

    while (1) {
      if (!(socketList[currentSocket % MAX_NUM_OF_SOCKETS].bound)) {
        // socket_t is just a reskinned uint8_t anyways so it's fine to typecast
        sock = (socket_t)(currentSocket % MAX_NUM_OF_SOCKETS);
        currentSocket++;
        return sock;
      }

      currentSocket++;
      counter++;

      if (counter > MAX_NUM_OF_SOCKETS) {
        // No available sockets, looped around too many times
        return NULL_SOCKET;
      }
    }
  }

  /**
   * Bind a socket with an address.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       you are binding.
   * @param
   *    socket_addr_t *addr: the source port and source address that
   *       you are biding to the socket, fd.
   * @Side Client/Server
   * @return error_t - SUCCESS if you were able to bind this socket, FAIL
   *       if you were unable to bind.
   */
  command error_t Transport.bind(socket_t fd, socket_addr_t * addr) {
    // error_t: 0 = success, 1 = failure
    if (fd >= MAX_NUM_OF_SOCKETS || fd < 0) {
      return FAIL; // Return an error if the fd is out of range
    }

    // Check if the socket is already bound
    if (socketList[fd].bound) {
      return FAIL; // Cannot bind if the socket is already bound
    }

    // Set state to Listen to prevent other sockets from binding
    socketList[fd].bound = 1; // bind fd
    socketList[fd].src = addr->port;

    return SUCCESS;
  }

  /**
   * Checks to see if there are socket connections to connect to and
   * if there is one, connect to it.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting an accept. remember, only do on listen.
   * @side Server
   * @return socket_t - returns a new socket if the connection is
   *    accepted. this socket is a copy of the server socket but with
   *    a destination associated with the destination address and port.
   *    if not return a null socket.
   */
  command socket_t Transport.accept(socket_t fd) {
    // This command is called by applications
    // The fd arg is the LISTEN socket with the port the application wants to
    // accept a new connection from
    connection_t newConn;
    socket_t newSocket = NULL_SOCKET;
    socket_addr_t socketAddr;

    int i;
    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      // Check if there is a CLOSED and unbound socket to fork
      if (socketList[i].state == CLOSED && !socketList[i].bound) {
        newSocket = i;
        break;
      }
    }

    if (fd == NULL_SOCKET || fd < 0 || fd > MAX_NUM_OF_SOCKETS) {
      return NULL_SOCKET;
    }
    if (getQueueSize(fd) == 0 || newSocket == NULL_SOCKET) {
      return NULL_SOCKET;
    }

    // Pop the first connection in the queue and bind it to a socket
    newConn = popFrontConnection(fd);
    socketAddr.addr = TOS_NODE_ID;
    socketAddr.port = newConn.destPort;
    call Transport.bind(newSocket, &socketAddr);

    // A hack to improve readability by initializing variables later
    if (1) {
      socket_store_t *boundSocket = &(socketList[newSocket]);
      uint8_t serverISN = call Random.rand16() % 256;
      uint8_t clientISN = newConn.seq;
      packTCP msg;

      uint8_t payloadSYN[0]; // SYN packets carry no payload
      uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
      uint16_t sizeTCP = sizeof(packTCP);

      // initialize the sequence numbers for both client and server
      boundSocket->lastRcvd = serverISN;
      boundSocket->nextExpected = clientISN + 1;

      /*
      void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
               uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
               uint8_t window, uint8_t * payload, uint8_t length)
      */
      makeTCP(&msg, TOS_NODE_ID, socketAddr.port, newConn.srcPort, SYNACK,
              clientISN + 1, serverISN, boundSocket->effectiveWindow,
              payloadSYN, 0);

      memcpy(payloadIP, (void *)(&msg), sizeTCP);

      call InternetProtocol.sendMessage(newConn.srcAddr, 10, PROTOCOL_TCP,
                                        payloadIP, sizeTCP);

      // Assign the destination field in socket_store_t
      boundSocket->dest.port = newConn.srcPort;
      boundSocket->dest.addr = newConn.srcAddr;

      boundSocket->state = SYN_RCVD;
    }

    printSockets(); // Remove later
    return newSocket;
  }

  /**
   * Write to the socket from a buffer. This data will eventually be
   * transmitted through your TCP implementation.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting a write.
   * @param
   *    uint8_t *buff: the buffer data that you are going to write from.
   * @param
   *    uint16_t bufflen: The amount of data that you are trying to
   *       submit.
   * @Side For your project, only client side. This could be both though.
   * @return uint16_t - return the amount of data you are able to write
   *    from the pass buffer. This may be shorter then bufflen
   */
  command uint16_t Transport.write(socket_t fd, uint8_t * buff,
                                   uint16_t bufflen) {
    // Called by applications
    socket_store_t *currSock;
    uint16_t trueBuffLen = bufflen;
    uint16_t i;
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return 0;
    }

    currSock = &socketList[fd];

    if (!(currSock->bound) || currSock->state != ESTABLISHED) {
      // socket has to be bound and already established
      return 0;
    }

    if (currSock->lastWritten + bufflen > SOCKET_BUFFER_SIZE) {
      // Buffer can't fit everything, have to shorten bufflen
      trueBuffLen = SOCKET_BUFFER_SIZE - currSock->lastWritten;
    }

    for (i = 0; i < trueBuffLen; i++) {
      // Copy buff into the socket buffer starting from lastWritten
      (currSock->sendBuff)[currSock->lastWritten + i] = buff[i];
    }
    return trueBuffLen;
  }

  error_t handleSYN(packTCP * msg) {
    uint8_t srcAddr = msg->srcAddr;
    uint8_t srcPort = msg->srcPort;
    uint8_t destPort = msg->destPort;

    // Sync packet, add the new connection request to the list of requests
    connection_t newConn;
    socket_t fd = NULL_SOCKET;

    uint16_t i;
    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      socket_store_t currSock = socketList[i];

      if (currSock.src == destPort && currSock.dest.port == srcPort &&
          currSock.dest.addr == srcAddr && currSock.bound) {

        if (currSock.state == ESTABLISHED) {
          // Basically, is there an existing socket already allocated to this
          // specific connection with the same ports and addresses?

          // If yes, then the SYN packet is a dupe of some sort
          dbg(GENERAL_CHANNEL, "dupe syn\n");
          return FAIL;
        }
      }

      // Find the LISTEN socket with the corresponding port
      if (currSock.state == LISTEN && currSock.src == destPort) {
        fd = i;
      }
    }

    if (fd == NULL_SOCKET) {
      // No matching LISTEN socket with same port, FAIL
      return FAIL;
    }
    // dbg(GENERAL_CHANNEL, "syn still valid with fd %i\n", fd);

    newConn.srcAddr = srcAddr;
    newConn.srcPort = srcPort;
    newConn.destPort = destPort;
    newConn.seq = msg->seq;

    if (getQueueSize(fd) < MAX_CONNECTIONS) {
      // Only push the new connections onto the queue if there is space
      pushBack(fd, newConn);

      signal Transport.newConnectionReceived();
    }

    return SUCCESS;
  }

  error_t handleACK(packTCP * msg) {
    int8_t srcAddr = msg->srcAddr;
    uint8_t srcPort = msg->srcPort;
    uint8_t destPort = msg->destPort;

    uint16_t i;
    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      socket_store_t *currSock = &socketList[i];
      if (currSock->src == destPort && currSock->dest.port == srcPort &&
          currSock->dest.addr == srcAddr && currSock->bound &&
          currSock->state != LISTEN) {

        if (currSock->state == SYN_RCVD) {
          // if state is SYN_RCVD, then this node is the server and this is the
          // last part of the three way handshake

          currSock->lastRcvd = currSock->lastRcvd + 1; // increase server seq
          currSock->nextExpected = msg->seq + 1;       // update server ack
          currSock->state = ESTABLISHED;
          dbg(GENERAL_CHANNEL,
              "Three way handshake complete, socket %i conn established\n", i);
          printSockets();

          return SUCCESS;

        } else if (currSock->state == ESTABLISHED) {
          // This code will be executed by the client

        } else {
          // ACK packets should only be received when the state is SYN_RCVD or
          // ESTABLISHED
          return FAIL;
        }
      }
    }

    return FAIL;
  }

  /**
   * This will pass the packet so you can handle it internally.
   * @param
   *    pack *package: the TCP packet that you are handling.
   * @Side Client/Server
   * @return uint16_t - return SUCCESS if you are able to handle this
   *    packet or FAIL if there are errors.
   */
  command error_t Transport.receive(uint8_t * payload) {
    // IP unwraps its header and passes the payload up to TCP
    packTCP *msg = (packTCP *)payload;
    uint8_t flag = msg->flag;

    if (flag == SYN) {
      return handleSYN(msg);
    } else if (flag == DATA) {
      // Needed because ACK packets don't carry data in this implementation
    } else if (flag == FIN) {
      // Close the connection
      // TODO
    } else if (flag == ACK) {
      return handleACK(msg);
    } else if (flag == SYNACK) {
      uint16_t i;
      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &(socketList[i]);

        if (currSock->src == msg->destPort &&
            currSock->dest.port == msg->srcPort &&
            currSock->dest.addr == msg->srcAddr && currSock->bound &&
            currSock->state == SYN_SENT) {
          // Checks if this is a SYN + ACK from a server to an existing
          // SYN_SENT socket

          packTCP msgAck;
          uint8_t payloadSYN[0];
          uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
          uint16_t sizeTCP = sizeof(packTCP);

          // Client sends one last ACK packet to server ACKing the server's
          // ISN
          // + 1 to complete the three way handshake
          makeTCP(&msgAck, TOS_NODE_ID, currSock->src, currSock->dest.port, ACK,
                  msg->seq + 1, currSock->lastSent + 1, 0, payloadSYN, 0);

          memcpy(payloadIP, (void *)(&msgAck), sizeTCP);

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP, sizeTCP);

          currSock->state = ESTABLISHED;
          currSock->lastSent = currSock->lastSent + 1;
          currSock->lastAck = msg->ack;

          dbg(GENERAL_CHANNEL, "SYN + ACK rcvd\n");
          printSockets();

          // TODO: signal some event that means you can send data

          return SUCCESS;
        }
      }
    } else if (flag == RST) {
      // RST requires a hard close
      call Transport.release(2);
    }

    return FAIL;
  }

  /**
   * Read from the socket and write this data to the buffer. This data
   * is obtained from your TCP implementation.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting a read.
   * @param
   *    uint8_t *buff: the buffer that is being written.
   * @param
   *    uint16_t bufflen: the amount of data that can be written to the
   *       buffer.
   * @Side For your project, only server side. This could be both though.
   * @return uint16_t - return the amount of data you are able to read
   *    from the pass buffer. This may be shorter then bufflen
   */
  command uint16_t Transport.read(socket_t fd, uint8_t * buff,
                                  uint16_t bufflen) {}

  /**
   * Attempts a connection to an address.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are attempting a connection with.
   * @param
   *    socket_addr_t *addr: the destination address and port where
   *       you will atempt a connection.
   * @side Client
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a connection with the fd passed, else return FAIL.
   */
  command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return FAIL;

    } else if (!socketList[fd].bound) {
      // Unbound, so fail
      return FAIL;

    } else {
      // Create a SYN packet with no payload and send it to the dest addr and
      // port
      packTCP msg;
      // Given that this is a SYN packet, most fields (like window) don't
      // matter
      uint8_t flag = SYN;
      // Randomize initial sequence number
      uint8_t initialSeq = call Random.rand16() % 256;
      uint8_t initialAck = 0;
      uint8_t window = 0;

      socket_store_t *socket = &(socketList[fd]);
      uint8_t srcPort = socket->src;
      uint8_t destPort = addr->port;

      // Headers for IP
      uint16_t destAddress = addr->addr;
      uint8_t TTL = 10;
      uint16_t protocol = PROTOCOL_TCP;

      uint8_t payloadSYN[0]; // SYN packets carry no payload

      uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
      uint16_t sizeTCP = sizeof(packTCP);

      makeTCP(&msg, TOS_NODE_ID, srcPort, destPort, flag, initialAck,
              initialSeq, window, payloadSYN, 0);

      memcpy(payloadIP, (void *)(&msg), sizeTCP);

      call InternetProtocol.sendMessage(destAddress, TTL, protocol, payloadIP,
                                        sizeTCP);

      // Assign the destination field in socket_store_t
      socket->dest.port = addr->port;
      socket->dest.addr = addr->addr;
      socket->lastSent = initialSeq;

      socket->state = SYN_SENT;

      return SUCCESS;
    }
  }

  /**
   * Closes the socket.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t Transport.close(socket_t fd) {}

  /**
   * A hard close, which is not graceful. This portion is optional.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t Transport.release(socket_t fd) {}

  /**
   * Listen to the socket and wait for a connection.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Server
   * @return error_t - returns SUCCESS if you are able change the state
   *   to listen else FAIL.
   */
  command error_t Transport.listen(socket_t fd) {
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return FAIL;
    }

    if (!socketList[fd].bound) {
      // Unbound, so fail
      return FAIL;
    }

    socketList[fd].state = LISTEN;
    return SUCCESS;
  }
}
