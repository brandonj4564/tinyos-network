#include "../../includes/packet.h"
#include "../../includes/socket.h"

module TransportP {
  provides interface Transport;

  uses interface Boot;
  uses interface InternetProtocol;
  uses interface Timer<TMilli> as PacketTimeout;
  uses interface Timer<TMilli> as WaitClose;
  uses interface Random;
  uses interface List<socket_t> as ClosingQueue;
  uses interface List<packTCP *> as PacketBuffer;
}

implementation {
  enum {
    // Flags
    SYN = 1,
    ACK = 2,
    SYNACK = 3,
    FIN = 4,
    RST = 5,
    DATA = 6,
    FINACK = 7,
    WIN = 8, // Sliding Window flag
    WINACK = 9,

    MAX_NUM_TIMESTAMPS = 30,
  };

  void printSocketFlag(char *str, uint8_t flag) {
    switch (flag) {
    case UNINIT:
      dbg(TRANSPORT_CHANNEL, "%sUNINIT\n", str);
      return;
    case NO_SEND_DATA:
      dbg(TRANSPORT_CHANNEL, "%sNO_SEND_DATA\n", str);
      return;
    case NO_RCVD_DATA:
      dbg(TRANSPORT_CHANNEL, "%sNO_RCVD_DATA\n", str);
      return;
    case BUFFER_FULL:
      dbg(TRANSPORT_CHANNEL, "%sBUFFER_FULL\n", str);
      return;
    case DATA_AVAIL:
      dbg(TRANSPORT_CHANNEL, "%sDATA_AVAIL\n", str);
      return;
    }
  }

  void printSocketState(char *str, uint8_t flag) {
    switch (flag) {
    case CLOSED:
      dbg(TRANSPORT_CHANNEL, "%sCLOSED\n", str);
      return;
    case LISTEN:
      dbg(TRANSPORT_CHANNEL, "%sLISTEN\n", str);
      return;
    case ESTABLISHED:
      dbg(TRANSPORT_CHANNEL, "%sESTABLISHED\n", str);
      return;
    case SYN_SENT:
      dbg(TRANSPORT_CHANNEL, "%sSYN_SENT\n", str);
      return;
    case SYN_RCVD:
      dbg(TRANSPORT_CHANNEL, "%sSYN_RCVD\n", str);
      return;
    case FIN_WAIT_1:
      dbg(TRANSPORT_CHANNEL, "%sFIN_WAIT_1\n", str);
      return;
    case FIN_WAIT_2:
      dbg(TRANSPORT_CHANNEL, "%sFIN_WAIT_2\n", str);
      return;
    case CLOSE_WAIT:
      dbg(TRANSPORT_CHANNEL, "%sCLOSE_WAIT\n", str);
      return;
    case TIME_WAIT:
      dbg(TRANSPORT_CHANNEL, "%sTIME_WAIT\n", str);
      return;
    }
  }

  void printPacketFlag(char *str, uint8_t flag) {
    switch (flag) {
    case SYN:
      dbg(TRANSPORT_CHANNEL, "%sSYN\n", str);
      return;
    case ACK:
      dbg(TRANSPORT_CHANNEL, "%sACK\n", str);
      return;
    case SYNACK:
      dbg(TRANSPORT_CHANNEL, "%sSYNACK\n", str);
      return;
    case FIN:
      dbg(TRANSPORT_CHANNEL, "%sFIN\n", str);
      return;
    case RST:
      dbg(TRANSPORT_CHANNEL, "%sRST\n", str);
      return;
    case DATA:
      dbg(TRANSPORT_CHANNEL, "%sDATA\n", str);
      return;
    case FINACK:
      dbg(TRANSPORT_CHANNEL, "%sFINACK\n", str);
      return;
    case WIN:
      dbg(TRANSPORT_CHANNEL, "%sWIN\n", str);
      return;
    case WINACK:
      dbg(TRANSPORT_CHANNEL, "%sWINACK\n", str);
      return;
    }
  }

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
    Package->length = length;
    memcpy(Package->payload, payload, length);
  }

  const uint16_t CLOSE_WAIT_TIME = 6000; // ms

  // Checks if the handlePacket task is already posted
  bool handlingPacket = FALSE;

  // Tracks if a socket has had its entire window acked. If not, then it cannot
  // send any further packets. slidingWindowLastPacket keeps track of the last
  // packet in the window that needs to be acked.
  bool slidingWindowAllowSend[MAX_NUM_OF_SOCKETS];
  uint8_t slidingWindowLastPacket[MAX_NUM_OF_SOCKETS];

  /*
  -------------------- CONNECTION SECTION --------------------
  */

  // A FIFO queue for each potential socket
  connection_t connectionList[MAX_NUM_OF_SOCKETS][MAX_CONNECTIONS];
  uint16_t connectionListIndex[MAX_NUM_OF_SOCKETS];

  // These functions have to be reimplemented because each LISTEN socket needs
  // its own queue

  int getQueueSize(socket_t fd) {
    if (fd >= 0 && fd < MAX_NUM_OF_SOCKETS) {
      return connectionListIndex[fd];
    }
    return NULL_SOCKET;
  }

  void printConnectionList(socket_t fd) {
    uint16_t i;

    for (i = 0; i < getQueueSize(fd); i++) {
      dbg(TRANSPORT_CHANNEL, "-------NEW CONNECTION-------\n");
      dbg(TRANSPORT_CHANNEL, "connection src addr: %u\n",
          connectionList[fd][i].srcAddr);
      dbg(TRANSPORT_CHANNEL, "connection src port: %u\n",
          connectionList[fd][i].srcPort);
      dbg(TRANSPORT_CHANNEL, "connection dest port: %u\n",
          connectionList[fd][i].destPort);
    }
  }

  connection_t popFrontConnection(socket_t fd) {
    connection_t returnVal;
    uint16_t i;
    uint16_t size = getQueueSize(fd);
    // printConnectionList(fd);

    returnVal = connectionList[fd][0];
    if (size > 0 && size != NULL_SOCKET) {
      // Move everything to the left.
      for (i = 0; i < size - 1; i++) {
        connectionList[fd][i].srcAddr = connectionList[fd][i + 1].srcAddr;
        connectionList[fd][i].srcPort = connectionList[fd][i + 1].srcPort;
        connectionList[fd][i].destPort = connectionList[fd][i + 1].destPort;
        connectionList[fd][i].seq = connectionList[fd][i + 1].seq;
      }
      connectionListIndex[fd] = connectionListIndex[fd] - 1;
    }

    return returnVal;
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

      // dbg(TRANSPORT_CHANNEL, "pushback connection src addr: %u\n",
      //     connectionList[fd][ind].srcAddr);
      // dbg(TRANSPORT_CHANNEL, "pushback connection src port: %u\n",
      //     connectionList[fd][ind].srcPort);
      // dbg(TRANSPORT_CHANNEL, "pushback connection dest port: %u\n",
      //     connectionList[fd][ind].destPort);

      connectionListIndex[fd] = connectionListIndex[fd] + 1;
    }
  }

  /*
  -------------------- END OF CONNECTION SECTION --------------------
  */

  socket_store_t socketList[MAX_NUM_OF_SOCKETS];
  // currentSocket is used to index socketList
  uint8_t currentSocket = 0;

  error_t updateRTT(socket_t fd, uint32_t timeSent) {
    uint32_t timeNow;
    float smoothingFactor = 0.2;
    socket_store_t *currSock;

    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return FAIL;
    }

    currSock = &socketList[fd];

    // Update RTT based on the time it arrived, timeNow, and the time it was
    // sent
    timeNow = call PacketTimeout.getNow();
    currSock->RTT = smoothingFactor * (timeNow - timeSent) +
                    (1 - smoothingFactor) * currSock->RTT;

    dbg(TRANSPORT_CHANNEL, "Socket %u new RTT: %u\n", fd, currSock->RTT);

    return SUCCESS;
  }

  /*
  -------------------- TIMESTAMP SECTION --------------------
  */
  typedef struct timestamp_t {
    bool bound;
    uint8_t flag;
    socket_t fd;

    // This is the information needed per timestamp to identify the packet
    uint8_t srcPort;
    uint8_t destAddr;
    uint8_t destPort;

    // Packet index of write buffer and len
    uint8_t nextSend;
    uint8_t nextWritten;
    uint8_t nextAck;
    uint8_t nextExpected;
    uint8_t length;
    uint8_t effectiveWindow;

    uint32_t timeSent;
  } timestamp_t;

  timestamp_t timestampList[MAX_NUM_TIMESTAMPS];
  uint16_t timestampIndex = 0;
  bool timestampEmpty = TRUE;
  const uint16_t TIMEOUT_TIMER = 4000;

  uint16_t timestampListSize() {
    uint16_t i;
    uint16_t size = 0;

    for (i = 0; i < MAX_NUM_TIMESTAMPS; i++) {
      if (timestampList[i].bound) {
        size++;
      }
    }

    return size;
  }

  void resendPacket(timestamp_t * currStamp) {
    packTCP msg;
    uint8_t flag = currStamp->flag;

    uint8_t payloadTCP[currStamp->length];
    uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
    uint16_t sizeTCP = sizeof(packTCP);

    uint8_t ack = 0;
    uint8_t len = currStamp->length;

    if (!currStamp->bound) {
      return;
    }

    /*
    void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
             uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
             uint8_t window, uint8_t * payload, uint8_t length)
    */

    if (flag == DATA) {
      // Put the data in the payload again
      uint8_t nextSend = currStamp->nextSend;
      uint16_t payloadSizeTCP = currStamp->length;

      uint8_t *sendBuff;
      uint8_t i;

      sendBuff = (&socketList[currStamp->fd])->sendBuff;
      // dbg(TRANSPORT_CHANNEL, "payloadSizeTCP: %u\n", payloadSizeTCP);
      for (i = 0; i < payloadSizeTCP; i++) {
        // Sequence number is the start of the data read
        payloadTCP[i] = sendBuff[(nextSend + i) % SOCKET_BUFFER_SIZE];
      }

      ack = currStamp->nextExpected + currStamp->length;

    } else if (flag == ACK) {
      ack = currStamp->nextExpected;
      // len = 0;
    } else if (flag == SYN) {
      ack = 0;
      len = 0;
    } else if (flag == SYNACK) {
      ack = currStamp->nextExpected;
      len = 0;
    } else if (flag == FIN) {
      ack = currStamp->nextExpected;
      len = 0;
    } else if (flag == RST) {
      // TODO lol
      // actually maybe this doesn't even need a resend
    }

    dbg(TRANSPORT_CHANNEL, "---------RESENDING TIMESTAMP---------\n");
    dbg(TRANSPORT_CHANNEL, "socket: %u\n", currStamp->fd);
    dbg(TRANSPORT_CHANNEL, "TS srcPort: %u\n", currStamp->srcPort);
    dbg(TRANSPORT_CHANNEL, "TS destAddr: %u\n", currStamp->destAddr);
    dbg(TRANSPORT_CHANNEL, "TS destPort: %u\n", currStamp->destPort);
    printPacketFlag("TS flag: ", flag);
    dbg(TRANSPORT_CHANNEL, "TS nextSend: %u\n", currStamp->nextSend);
    dbg(TRANSPORT_CHANNEL, "TS length: %u\n", len);

    makeTCP(&msg, TOS_NODE_ID, currStamp->srcPort, currStamp->destPort,
            currStamp->flag, ack, currStamp->nextSend,
            currStamp->effectiveWindow, payloadTCP, len);

    memcpy(payloadIP, (void *)(&msg), sizeTCP + len);

    call InternetProtocol.sendMessage(currStamp->destAddr, 10, PROTOCOL_TCP,
                                      payloadIP, sizeTCP + len);

    // No, no. Actually, do not reset the time sent. -Me, 2 days later
    // currStamp->timeSent = call PacketTimeout.getNow(); // reset timesent
  }

  void printPacket(packTCP * msg) {
    dbg(TRANSPORT_CHANNEL, "----------PACKET----------\n");
    printPacketFlag("flag: ", msg->flag);
    dbg(TRANSPORT_CHANNEL, "srcAddr: %u | srcPort: %u | destPort: %u\n",
        msg->srcAddr, msg->srcPort, msg->destPort);
    dbg(TRANSPORT_CHANNEL, "seq: %u | ack: %u | window: %u | length: %u\n",
        msg->seq, msg->ack, msg->window, msg->length);
  }

  task void handlePacketTimeout() {
    uint16_t i;
    uint32_t timeNow;

    if (timestampEmpty) {
      // If there are no packets in flight, do nothing
      return;
    }

    timeNow = call PacketTimeout.getNow();

    for (i = 0; i < MAX_NUM_TIMESTAMPS; i++) {
      timestamp_t *currStamp = &timestampList[i];
      if (currStamp->bound) {
        // dbg(TRANSPORT_CHANNEL, "timeNow: %u\n", timeNow);
        // dbg(TRANSPORT_CHANNEL, "Packet time + RTT: %u\n",
        //     currStamp->timeSent + socketList[currStamp->fd].RTT);

        if (currStamp->timeSent + socketList[currStamp->fd].RTT <= timeNow) {
          // The packet has timed out
          // dbg(TRANSPORT_CHANNEL, "Packet timed out from socket %u\n",
          //     currStamp->fd);

          resendPacket(currStamp);
        }
      }
    }

    if (timestampListSize() == 0) {
      timestampEmpty = TRUE;
    } else {
      timestampEmpty = FALSE; // just in case
      // dbg(TRANSPORT_CHANNEL, "PacketTimeout restarted\n");
      call PacketTimeout.startOneShot(TIMEOUT_TIMER);
    }
  }

  event void PacketTimeout.fired() {
    // Keep event code as short as possible
    post handlePacketTimeout();
  }

  // Creates a timestamp for a newly sent packet
  /**
   * Checks to see if there are socket connections to connect to and
   * if there is one, connect to it.
   * @param
   *    socket_t fd
   * @param
   *    uint8_t flag
   * @param
   *    uint8_t nextSend
   * @param
   *    uint8_t length
   * @return error_t
   */
  error_t createTimestamp(socket_t fd, uint8_t flag, uint8_t nextSend,
                          uint8_t length) {
    uint8_t counter = 0;
    socket_store_t *currSock = &socketList[fd];
    timestamp_t *currStamp;

    while (1) {
      if (!timestampList[timestampIndex % MAX_NUM_TIMESTAMPS].bound) {
        currStamp = &timestampList[timestampIndex % MAX_NUM_TIMESTAMPS];
        timestampIndex++;
        break;
      }
      counter++;
      timestampIndex++;

      if (counter > MAX_NUM_TIMESTAMPS + 1) {
        // No free timestamps
        return FAIL;
      }
    }

    currStamp->bound = TRUE;
    currStamp->srcPort = currSock->src;
    currStamp->destAddr = currSock->dest.addr;
    currStamp->destPort = currSock->dest.port;
    currStamp->flag = flag;
    currStamp->nextSend = nextSend;
    currStamp->nextWritten = currSock->nextWritten;
    currStamp->nextAck = currSock->nextAck;
    currStamp->nextExpected = currSock->nextExpected;
    currStamp->effectiveWindow = currSock->effectiveWindow;
    currStamp->length = length;
    currStamp->fd = fd;

    currStamp->timeSent = call PacketTimeout.getNow();

    timestampEmpty = FALSE;

    dbg(TRANSPORT_CHANNEL, "---------ADD TIMESTAMP---------\n");
    dbg(TRANSPORT_CHANNEL, "TS socket: %u\n", fd);
    dbg(TRANSPORT_CHANNEL, "TS srcPort: %u\n", currSock->src);
    dbg(TRANSPORT_CHANNEL, "TS destAddr: %u\n", currSock->dest.addr);
    dbg(TRANSPORT_CHANNEL, "TS destPort: %u\n", currSock->dest.port);
    printPacketFlag("TS flag: ", currStamp->flag);

    dbg(TRANSPORT_CHANNEL, "TS nextSend: %u\n", nextSend);
    dbg(TRANSPORT_CHANNEL, "TS length: %u\n", length);

    if (!(call PacketTimeout.isRunning())) {
      call PacketTimeout.startOneShot(TIMEOUT_TIMER);
    }

    return SUCCESS;
  }

  // Removing the timestamp, maybe the packet was acked or it timed out
  error_t removeTimestamp(socket_t fd, uint8_t flag, uint8_t nextSend,
                          uint8_t length) {
    socket_store_t *currSock = &socketList[fd];
    timestamp_t *currStamp;
    uint16_t i;

    for (i = 0; i < MAX_NUM_TIMESTAMPS; i++) {
      if (timestampList[i].bound) {
        currStamp = &timestampList[i];

        if (currStamp->srcPort == currSock->src &&
            currStamp->destAddr == currSock->dest.addr &&
            currStamp->destPort == currSock->dest.port &&
            currStamp->flag == flag && currStamp->nextSend == nextSend) {
          // Check for exact packet match

          // Remove the timestamp
          currStamp->bound = FALSE;
          updateRTT(fd, currStamp->timeSent);

          if (timestampListSize() == 0) {
            // no more bound timestamps
            timestampEmpty = TRUE;
          }

          dbg(TRANSPORT_CHANNEL, "---------REMOVE TIMESTAMP---------\n");
          dbg(TRANSPORT_CHANNEL, "TS socket: %u\n", fd);
          dbg(TRANSPORT_CHANNEL, "TS srcPort: %u\n", currSock->src);
          dbg(TRANSPORT_CHANNEL, "TS destAddr: %u\n", currSock->dest.addr);
          dbg(TRANSPORT_CHANNEL, "TS destPort: %u\n", currSock->dest.port);
          printPacketFlag("TS flag: ", flag);
          dbg(TRANSPORT_CHANNEL, "TS nextSend: %u\n", nextSend);
          dbg(TRANSPORT_CHANNEL, "TS length: %u\n", length);
          return SUCCESS;
        }
      }
    }

    dbg(TRANSPORT_CHANNEL, "---------TIMESTAMP FAIL REMOVED---------\n");
    dbg(TRANSPORT_CHANNEL, "TS socket: %u\n", fd);
    dbg(TRANSPORT_CHANNEL, "TS srcPort: %u\n", currSock->src);
    dbg(TRANSPORT_CHANNEL, "TS destAddr: %u\n", currSock->dest.addr);
    dbg(TRANSPORT_CHANNEL, "TS destPort: %u\n", currSock->dest.port);
    printPacketFlag("TS flag: ", flag);
    dbg(TRANSPORT_CHANNEL, "TS nextSend: %u\n", nextSend);
    dbg(TRANSPORT_CHANNEL, "TS length: %u\n", length);
    return FAIL;
  }

  error_t removeAllTimestamps(socket_t fd) {
    socket_store_t *currSock = &socketList[fd];
    timestamp_t *currStamp;
    uint16_t i;

    for (i = 0; i < MAX_NUM_TIMESTAMPS; i++) {
      if (timestampList[i].bound) {
        currStamp = &timestampList[i];

        if (currStamp->srcPort == currSock->src &&
            currStamp->destAddr == currSock->dest.addr &&
            currStamp->destPort == currSock->dest.port) {

          currStamp->bound = FALSE;
          dbg(TRANSPORT_CHANNEL, "---------REMOVING ALL TIMESTAMPS---------\n");
          dbg(TRANSPORT_CHANNEL, "TS socket: %u\n", fd);
          dbg(TRANSPORT_CHANNEL, "TS srcPort: %u\n", currSock->src);
          dbg(TRANSPORT_CHANNEL, "TS destAddr: %u\n", currSock->dest.addr);
          dbg(TRANSPORT_CHANNEL, "TS destPort: %u\n", currSock->dest.port);
          printPacketFlag("TS flag: ", currStamp->flag);
          dbg(TRANSPORT_CHANNEL, "TS nextSend: %u\n", currStamp->nextSend);
          dbg(TRANSPORT_CHANNEL, "TS length: %u\n", currStamp->length);
        }
      }
    }

    if (timestampListSize() == 0) {
      // no more bound timestamps
      timestampEmpty = TRUE;
    }

    return SUCCESS;
  }

  /*
  -------------------- END OF TIMESTAMP SECTION --------------------
  */

  void printSockets() {
    int i;
    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      if (socketList[i].bound) {
        dbg(TRANSPORT_CHANNEL, "---------SOCKET---------\n");
        dbg(TRANSPORT_CHANNEL, "Socket fd: %i\n", i);
        printSocketState("Socket state: ", socketList[i].state);
        printSocketFlag("Socket flag: ", socketList[i].flag);
        dbg(TRANSPORT_CHANNEL, "Socket port: %i\n", socketList[i].src);
        dbg(TRANSPORT_CHANNEL, "Socket dest addr: %i\n",
            socketList[i].dest.addr);
        dbg(TRANSPORT_CHANNEL, "Socket dest port: %i\n",
            socketList[i].dest.port);

        // Sender portion
        dbg(TRANSPORT_CHANNEL, "Sender portion\n");
        dbg(TRANSPORT_CHANNEL, "Socket next written: %i\n",
            socketList[i].nextWritten);
        dbg(TRANSPORT_CHANNEL, "Socket next ack rcvd: %i\n",
            socketList[i].nextAck);
        dbg(TRANSPORT_CHANNEL, "Socket next seq sent: %i\n",
            socketList[i].nextSend);

        // Receiver portion
        dbg(TRANSPORT_CHANNEL, "Receiver portion\n");
        dbg(TRANSPORT_CHANNEL, "Socket next read: %i\n",
            socketList[i].nextRead);
        dbg(TRANSPORT_CHANNEL, "Socket next seq rcvd: %i\n",
            socketList[i].nextRcvd);
        dbg(TRANSPORT_CHANNEL, "Socket next expected: %i\n",
            socketList[i].nextExpected);

        dbg(TRANSPORT_CHANNEL, "Socket RTT: %i\n", socketList[i].RTT);
        dbg(TRANSPORT_CHANNEL, "Socket adv window: %i\n",
            socketList[i].effectiveWindow);
      }
    }
  }

  event void Boot.booted() {
    uint8_t i;

    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      // Initialize all sockets as being free and with default values
      socketList[i].state = CLOSED;
      socketList[i].bound = FALSE;
      socketList[i].flag = UNINIT;
      socketList[i].src = 0;
      socketList[i].dest.port = 0;
      socketList[i].dest.addr = 0;

      // Initialize buffer pointers and counters
      socketList[i].nextWritten = 0;
      socketList[i].nextAck = 0;
      socketList[i].nextSend = 0;
      socketList[i].nextRead = 0;
      socketList[i].nextRcvd = 0;
      socketList[i].nextExpected = 0;

      // Set RTT and window values to 0 or default
      socketList[i].RTT = 300; // ms
      socketList[i].effectiveWindow = SOCKET_BUFFER_SIZE - 1;

      // Optionally initialize buffers to zero
      memset(socketList[i].sendBuff, 0, SOCKET_BUFFER_SIZE);
      memset(socketList[i].rcvdBuff, 0, SOCKET_BUFFER_SIZE);

      connectionListIndex[i] = 0;
      slidingWindowAllowSend[i] = TRUE;
    }

    for (i = 0; i < MAX_NUM_TIMESTAMPS; i++) {
      timestampList[i].bound = FALSE;
    }
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

    // printSockets();

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
      uint8_t serverISN = call Random.rand16() % SOCKET_BUFFER_SIZE;
      // uint8_t serverISN = 0;
      uint8_t clientISN = newConn.seq;
      packTCP msg;

      uint8_t payloadSYN[0]; // SYN packets carry no payload
      uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
      uint16_t sizeTCP = sizeof(packTCP);

      // initialize the sequence numbers for both client and server
      boundSocket->nextSend = serverISN;
      boundSocket->nextExpected = clientISN + 1;
      boundSocket->nextRead = serverISN;
      boundSocket->nextRcvd = serverISN;

      /*
      void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
               uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
               uint8_t window, uint8_t * payload, uint8_t length)
      */
      makeTCP(&msg, TOS_NODE_ID, socketAddr.port, newConn.srcPort, SYNACK,
              clientISN + 1, serverISN, SOCKET_BUFFER_SIZE - 1, payloadSYN, 0);

      memcpy(payloadIP, (void *)(&msg), sizeTCP);

      call InternetProtocol.sendMessage(newConn.srcAddr, 10, PROTOCOL_TCP,
                                        payloadIP, sizeTCP);

      // Assign the destination field in socket_store_t
      boundSocket->dest.port = newConn.srcPort;
      boundSocket->dest.addr = newConn.srcAddr;

      createTimestamp(newSocket, SYNACK, 0, 0);
      if (!(call PacketTimeout.isRunning())) {
        call PacketTimeout.startOneShot(TIMEOUT_TIMER);
      }

      boundSocket->state = SYN_RCVD;
    }

    // printSockets(); // Remove later
    return newSocket;
  }

  // Call this function to send data on a client socket
  error_t sendData(socket_t fd) {
    socket_store_t *currSock;
    packTCP datagram;

    // subtract both TCP and IP headers
    uint16_t payloadSizeTCP =
        PACKET_MAX_PAYLOAD_SIZE - sizeof(packTCP) - sizeof(packIP);
    uint8_t payloadTCP[payloadSizeTCP];
    uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];
    uint8_t *sendBuff;
    uint8_t nextSend;
    uint8_t nextWritten;
    uint8_t nextAck;
    uint8_t effectiveWindow;
    uint8_t nextExpected;

    uint16_t i;
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return FAIL;
    }

    if (!slidingWindowAllowSend[fd]) {
      // do not send any data until the final packet has been acked
      // dbg(TRANSPORT_CHANNEL, "sendData ruined! Socket %u\n", fd);
      return FAIL;
    }

    currSock = &socketList[fd];

    if (!(currSock->bound) || currSock->state != ESTABLISHED ||
        currSock->flag == NO_SEND_DATA) {
      // socket has to be bound and already established and have data to send
      return FAIL;
    } else if (currSock->nextWritten == currSock->nextAck) {
      // no data to send yet the flag is not NO_SEND_DATA
      return FAIL;
    }

    effectiveWindow = currSock->effectiveWindow;
    nextWritten = currSock->nextWritten;
    nextAck = currSock->nextAck;
    nextExpected = currSock->nextExpected;

    while (effectiveWindow > 0) {
      // Resend data until the effective window is full or there is no more data
      // to send
      nextSend = currSock->nextSend;
      payloadSizeTCP =
          PACKET_MAX_PAYLOAD_SIZE - sizeof(packTCP) - sizeof(packIP);
      if (effectiveWindow < payloadSizeTCP) {
        // limit the payload to the effective window size
        payloadSizeTCP = effectiveWindow;
      }

      if (nextSend == nextWritten) {
        // Not enough data in the send buffer to fill the entire window, so
        // break out of the loop early
        break;
      }

      // This if statement is checking if there is enough written data to fill
      // an entire packet, otherwise fill up the packet enough until nextSend =
      // nextWritten
      if (nextSend < nextWritten && nextWritten > nextAck &&
          nextSend + payloadSizeTCP >= nextWritten) {
        // Not enough written data to fill payload, limit payloadSizeTCP
        payloadSizeTCP = nextWritten - nextSend;

      } else if (nextWritten < nextAck) {
        // Buffer has wrapped around
        // {||||||nextWritten       nextAck||||||}
        if (nextSend > nextWritten &&
            nextSend + payloadSizeTCP >= SOCKET_BUFFER_SIZE &&
            (nextSend + payloadSizeTCP) % SOCKET_BUFFER_SIZE >= nextWritten) {
          // nextSend hasn't wrapped around yet, but will exceed nextWritten
          // when it does wrap
          payloadSizeTCP = (SOCKET_BUFFER_SIZE - nextSend) + nextWritten;
        } else if (nextSend < nextWritten &&
                   nextSend + payloadSizeTCP >= nextWritten) {
          payloadSizeTCP = nextWritten - nextSend;
        }
      }

      sendBuff = currSock->sendBuff;
      // dbg(TRANSPORT_CHANNEL, "payloadSizeTCP: %u\n", payloadSizeTCP);
      for (i = 0; i < payloadSizeTCP; i++) {
        // Sequence number is the start of the data read
        payloadTCP[i] = sendBuff[(nextSend + i) % SOCKET_BUFFER_SIZE];
      }

      nextExpected = (nextExpected + payloadSizeTCP) % SOCKET_BUFFER_SIZE;

      /*
      void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
                 uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
                 uint8_t window, uint8_t * payload, uint8_t length)
      */
      makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port, DATA,
              nextExpected, nextSend, 0, payloadTCP, payloadSizeTCP);

      memcpy(payloadIP, (void *)(&datagram), payloadSizeTCP + sizeof(packTCP));

      call InternetProtocol.sendMessage(currSock->dest.addr, 10, PROTOCOL_TCP,
                                        payloadIP,
                                        payloadSizeTCP + sizeof(packTCP));
      createTimestamp(fd, DATA, nextSend, payloadSizeTCP);

      slidingWindowLastPacket[fd] = nextSend;
      currSock->nextSend =
          (currSock->nextSend + payloadSizeTCP) % SOCKET_BUFFER_SIZE;

      // Some of the effective window has been filled by the sent packet
      effectiveWindow = effectiveWindow - payloadSizeTCP;
    }

    // Disallow sending more packets until this group of packets is fully acked
    slidingWindowAllowSend[fd] = FALSE;

    return SUCCESS;
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
    uint8_t nextWritten;
    uint8_t nextAck;
    uint8_t *sendBuff;
    uint8_t newFlag = DATA_AVAIL;
    uint16_t i;
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return 0;
    }

    currSock = &socketList[fd];
    nextWritten = currSock->nextWritten;
    nextAck = currSock->nextAck;

    if (!(currSock->bound) || currSock->state != ESTABLISHED ||
        currSock->flag == BUFFER_FULL || bufflen == 0) {
      // socket has to be bound and already established and have room
      return 0;
    }

    if (bufflen >= SOCKET_BUFFER_SIZE) {
      // cap the buff len
      trueBuffLen = SOCKET_BUFFER_SIZE - 1;
      newFlag = BUFFER_FULL;
    }

    // dbg(TRANSPORT_CHANNEL, "trueBuffLen before if: %u\n", trueBuffLen);
    // dbg(TRANSPORT_CHANNEL, "nextWritten: %u\n", nextWritten);
    // dbg(TRANSPORT_CHANNEL, "nextAck: %u\n", nextAck);

    if (nextWritten >= nextAck &&
        nextWritten + trueBuffLen > SOCKET_BUFFER_SIZE) {
      // Basically, if the end index of the buffer starts out greater than the
      // start index and writing bufflen causes nextWritten to wrap around the
      // circular buffer
      uint8_t wrappedAroundnextWritten =
          (nextWritten + trueBuffLen) % SOCKET_BUFFER_SIZE;
      if (wrappedAroundnextWritten >= nextAck) {
        // If, even after having wrapped around, the nextWritten ends up greater
        // than nextAck again, then the buffer doesn't have enough space
        uint16_t overflow = wrappedAroundnextWritten - nextAck + 1;

        trueBuffLen = trueBuffLen - overflow;
        newFlag = BUFFER_FULL;
      }
    } else if (nextWritten < nextAck && nextWritten + trueBuffLen >= nextAck) {
      // If the end index starts lower than the start (wrap around) but ends up
      // greater due to overflow
      uint16_t overflow = nextWritten + trueBuffLen - nextAck + 1;
      // imagine nextWritten = 2, nextAck = 5, trueBuffLen = 8
      // overflow = 10 - 5 = 5
      // trueBuffLen = 8 - 5 = 3

      trueBuffLen = trueBuffLen - overflow;
      newFlag = BUFFER_FULL;
    }
    dbg(TRANSPORT_CHANNEL, "trueBuffLen after if: %u\n", trueBuffLen);

    sendBuff = currSock->sendBuff;
    for (i = 0; i < trueBuffLen; i++) {
      sendBuff[(nextWritten + i) % SOCKET_BUFFER_SIZE] = buff[i];
    }

    currSock->nextWritten =
        (currSock->nextWritten + trueBuffLen) % SOCKET_BUFFER_SIZE;

    // printSockets();
    if (currSock->flag == NO_SEND_DATA) {
      currSock->flag = newFlag;
      sendData(fd);
    }
    currSock->flag = newFlag;

    return trueBuffLen;
  }

  // Call this function when ending the handlePacket() task early
  // Have to define this function before handlePacket() but implement it later
  void endHandlePacket();

  task void handlePacket() {
    packTCP *msg = call PacketBuffer.popfront();
    uint8_t flag = msg->flag;
    uint8_t srcAddr = msg->srcAddr;
    uint8_t srcPort = msg->srcPort;
    uint8_t destPort = msg->destPort;
    uint16_t i;

    handlingPacket = TRUE;

    printPacket(msg);

    if (flag == SYN) {
      // Sync packet, add the new connection request to the list of requests
      connection_t newConn;
      socket_t fd = NULL_SOCKET;

      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t currSock = socketList[i];

        if (currSock.src == destPort && currSock.dest.port == srcPort &&
            currSock.dest.addr == srcAddr && currSock.bound) {

          if (currSock.state == ESTABLISHED) {
            // Basically, is there an existing socket already allocated to
            // this specific connection with the same ports and addresses?

            // If yes, then the SYN packet is a dupe of some sort
            dbg(TRANSPORT_CHANNEL, "dupe syn, conn established already\n");

            endHandlePacket();
            return;
          }
        }

        // Find the LISTEN socket with the corresponding port
        if (currSock.state == LISTEN && currSock.src == destPort) {
          fd = i;
        }
      }

      if (fd == NULL_SOCKET) {
        // No matching LISTEN socket with same port, FAIL
        dbg(TRANSPORT_CHANNEL, "No matching listener socket.\n");
        endHandlePacket();
        return;
      }

      for (i = 0; i < getQueueSize(fd); i++) {
        connection_t currConn = connectionList[fd][i];
        if (currConn.srcAddr == srcAddr && currConn.srcPort == srcPort &&
            currConn.destPort == destPort && currConn.seq == msg->seq) {
          // is there already a connection request from this client
          dbg(TRANSPORT_CHANNEL, "dupe syn, conn already pending\n");
          endHandlePacket();
          return;
        }
      }

      // printPacket(msg);

      newConn.srcAddr = srcAddr;
      newConn.srcPort = srcPort;
      newConn.destPort = destPort;
      newConn.seq = msg->seq;

      if (getQueueSize(fd) < MAX_CONNECTIONS) {
        // Only push the new connections onto the queue if there is space
        pushBack(fd, newConn);

        signal Transport.newConnectionReceived(fd);
      }

      endHandlePacket();
      return;
    } else if (flag == DATA) {

      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        uint16_t j;
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {

          packTCP datagram;
          uint16_t sizeTCP = sizeof(packTCP);
          uint8_t payloadTCP[0];
          uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

          uint8_t *rcvdBuff = currSock->rcvdBuff;
          uint8_t msgLength = msg->length;
          dbg(TRANSPORT_CHANNEL, "DATA packet received\n");

          if (msg->seq != currSock->nextExpected) {
            // Is this an out-of-order DATA packet? If so, send an ack but don't
            // make any changes to the socket
            dbg(TRANSPORT_CHANNEL,
                "DATA packet out of order! Expected: %u. Received: %u\n",
                currSock->nextExpected, msg->seq);

            makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port,
                    ACK, (msg->seq + msgLength) % SOCKET_BUFFER_SIZE,
                    currSock->nextSend, currSock->effectiveWindow, payloadTCP,
                    0);
            datagram.length = msgLength;

            memcpy(payloadIP, (void *)(&datagram), sizeTCP + sizeof(packTCP));

            call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                              PROTOCOL_TCP, payloadIP, sizeTCP);

            // currSock->nextSend = currSock->nextSend + msgLength;

            endHandlePacket();
            return;
          }

          if (currSock->nextRcvd >= currSock->nextRead &&
              currSock->nextRcvd + msgLength > SOCKET_BUFFER_SIZE) {

            uint8_t wrappedAroundnextRcvd =
                (currSock->nextRcvd + msgLength) % SOCKET_BUFFER_SIZE;
            if (wrappedAroundnextRcvd >= currSock->nextRead) {

              uint16_t overflow =
                  wrappedAroundnextRcvd - currSock->nextRead + 1;

              msgLength = msgLength - overflow;
              currSock->flag = BUFFER_FULL;
            }
          } else if (currSock->nextRcvd < currSock->nextRead &&
                     currSock->nextRcvd + msgLength >= currSock->nextRead) {

            uint16_t overflow =
                currSock->nextRcvd + msgLength - currSock->nextRead + 1;
            msgLength = msgLength - overflow;
            currSock->flag = BUFFER_FULL;
          }

          for (j = 0; j < msgLength; j++) {
            rcvdBuff[(currSock->nextRcvd + j) % SOCKET_BUFFER_SIZE] =
                (msg->payload)[j];
          }

          currSock->nextExpected = (msg->seq + msgLength) % SOCKET_BUFFER_SIZE;
          currSock->nextRcvd =
              (currSock->nextRcvd + msgLength) % SOCKET_BUFFER_SIZE;
          currSock->effectiveWindow = currSock->effectiveWindow - msgLength;
          if (currSock->flag == NO_RCVD_DATA) {
            currSock->flag = DATA_AVAIL;
          }
          signal Transport.dataAvailable(i);

          /*
          void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
                    uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
                    uint8_t window, uint8_t * payload, uint8_t length)
          */
          makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port,
                  ACK, currSock->nextExpected, currSock->nextSend,
                  currSock->effectiveWindow, payloadTCP, 0);
          datagram.length = msgLength;
          // datagram.length = msg->length;

          memcpy(payloadIP, (void *)(&datagram), sizeTCP + sizeof(packTCP));

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP, sizeTCP);

          // TODO: Is this line below correct?
          currSock->nextSend = currSock->nextSend + msgLength;

          // printSockets();
          endHandlePacket();
          return;
        }
      }
      endHandlePacket();
      return;

    } else if (flag == FIN) {
      // Close the connection

      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {

          packTCP datagram;
          uint16_t sizeTCP = sizeof(packTCP);
          uint8_t payloadTCP[0];
          uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

          dbg(TRANSPORT_CHANNEL, "FIN packet received\n");

          makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port,
                  FINACK, currSock->nextExpected, currSock->nextSend,
                  currSock->effectiveWindow, payloadTCP, 0);

          memcpy(payloadIP, (void *)(&datagram), sizeTCP + sizeof(packTCP));

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP, sizeTCP);
          createTimestamp(i, FINACK, currSock->nextSend, 0);

          call ClosingQueue.pushback(i);
          if (currSock->state == ESTABLISHED) {
            // This is the initial recipient of the FIN packet
            currSock->state = CLOSE_WAIT;

            // Don't worry if all the data has been read yet, the app will
            // have to set a timer if it hasn't
            signal Transport.alertClose(i);
          } else if (currSock->state == FIN_WAIT_2) {
            // This is the second FIN packet which arrives back at the
            // original FIN sender
            currSock->state = TIME_WAIT;

            if (!(call WaitClose.isRunning())) {
              // only restart the timer if it is not currently in use
              call WaitClose.startOneShot(CLOSE_WAIT_TIME);
            }
          }

          endHandlePacket();
          return;
        }
      }

      endHandlePacket();
      return;

    } else if (flag == ACK) {
      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {

          if (currSock->state == SYN_RCVD) {
            // if state is SYN_RCVD, then this node is the server and this is
            // the last part of the three way handshake

            currSock->nextExpected = msg->seq;
            currSock->state = ESTABLISHED;
            currSock->flag = NO_RCVD_DATA;
            dbg(TRANSPORT_CHANNEL,
                "Three way handshake complete, socket %i conn established\n",
                i);
            // printPacket(msg);
            removeTimestamp(i, SYNACK, 0, 0);
            // printSockets();

            endHandlePacket();
            return;

          } else if (currSock->state == ESTABLISHED) {
            // This code will be executed by the client
            uint8_t ackSeq = msg->ack;
            uint8_t prevPacketNextSend =
                (ackSeq + SOCKET_BUFFER_SIZE - msg->length) %
                SOCKET_BUFFER_SIZE;

            // Check if ackSeq is what we expect
            // ackSeq must be equal to nextSend to count that packet as acked
            if (prevPacketNextSend != currSock->nextAck) {
              // This ack must be out of order or lost, either way it doesn't
              // match

              // TODO: I've realized that, if the rcvd buffer of the server
              // is temporarily full, the ack received back will not match with
              // currSock->nextSend because nextSend assumes the entire message
              // was put in the buffer rather than just a part. Need to fix.

              // this may also cause other problems idk lol
              dbg(TRANSPORT_CHANNEL, "Invalid ACK number: %u. Expected: %u\n",
                  ackSeq,
                  (currSock->nextAck + msg->length) % SOCKET_BUFFER_SIZE);
              endHandlePacket();
              return;
            }

            dbg(TRANSPORT_CHANNEL, "ACK FOR DATA RCVD! ACK: %u\n", ackSeq);
            // printPacket(msg);

            removeTimestamp(i, DATA, prevPacketNextSend, msg->length);

            // update nextAck, free up space in the sendBuffer
            currSock->nextAck = ackSeq;
            currSock->effectiveWindow = msg->window;

            if (currSock->nextWritten == ackSeq) {
              currSock->flag = NO_SEND_DATA;
            } else {
              currSock->flag = DATA_AVAIL;
            }

            // Data has been acked, more can be written
            signal Transport.bufferFreed(i);

            if (prevPacketNextSend == slidingWindowLastPacket[i]) {
              // entire group of packets has been acked, we can send more
              dbg(TRANSPORT_CHANNEL,
                  "Last packet %u acked, new sliding window %u can be sent!\n",
                  prevPacketNextSend, i);
              slidingWindowAllowSend[i] = TRUE;
            }
            sendData(i);
            // printSockets();

            endHandlePacket();
            return;
          } else if (currSock->state == CLOSE_WAIT) {
            // This is the server, receiving the ACK for its FINACK
            dbg(TRANSPORT_CHANNEL, "ACK for FINACK received at server.\n");
            removeTimestamp(i, FINACK, msg->ack, 0);

          } else if (currSock->state == TIME_WAIT) {
            // This is the client after receiving the FIN from the server,
            // receiving the ACK for its FINACK
            dbg(TRANSPORT_CHANNEL, "ACK for FINACK received at client.\n");
            removeTimestamp(i, FINACK, msg->ack, 0);

          } else {
            // ACK packets should only be received when the state is
            // SYN_RCVD or ESTABLISHED or one of the FIN states
            endHandlePacket();
            return;
          }
        }
      }

      endHandlePacket();
      return;
    } else if (flag == SYNACK) {
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

          // printPacket(msg);

          // Client sends one last ACK packet to server ACKing the server's
          // ISN to complete the three way handshake
          makeTCP(&msgAck, TOS_NODE_ID, currSock->src, currSock->dest.port, ACK,
                  msg->seq, currSock->nextSend, 0, payloadSYN, 0);

          memcpy(payloadIP, (void *)(&msgAck), sizeTCP);

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP, sizeTCP);

          removeTimestamp(i, SYN, currSock->nextSend, 0);

          currSock->state = ESTABLISHED;
          currSock->flag = NO_SEND_DATA;
          currSock->nextExpected = msg->seq; // client tracks server's seq
          currSock->effectiveWindow =
              msg->window; // client tracks server's window size

          signal Transport.connectionSuccess(i);
          // printSockets();
          endHandlePacket();
          return;
        }
      }

      endHandlePacket();
      return;
    } else if (flag == RST) {
      // RST requires a hard close
      call Transport.release(2);
    } else if (flag == FINACK) {

      dbg(TRANSPORT_CHANNEL, "FINACK arrived.\n");
      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {

          // Send an ACK for the FINACK (lol)
          packTCP datagram;
          uint8_t payloadTCP[0];
          uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

          makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port,
                  ACK, msg->seq, currSock->nextSend, currSock->effectiveWindow,
                  payloadTCP, 0);

          memcpy(payloadIP, (void *)(&datagram), sizeof(packTCP));

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP,
                                            sizeof(packTCP));

          if (currSock->state == FIN_WAIT_1) {
            currSock->state = FIN_WAIT_2;
            removeTimestamp(i, FIN, currSock->nextSend, 0);
            dbg(TRANSPORT_CHANNEL, "FIN initiator entering FIN_WAIT_2, now "
                                   "waiting for FIN from recipient.\n");
            // wait for FIN to arrive from other node (server)

          } else if (currSock->state == CLOSE_WAIT) {
            // Timer before going to closed state
            removeTimestamp(i, FIN, currSock->nextSend, 0);
            dbg(TRANSPORT_CHANNEL, "FIN recipient now shutting down.\n");
            if (!(call WaitClose.isRunning())) {
              call WaitClose.startOneShot(CLOSE_WAIT_TIME);
            }
          }

          endHandlePacket();
          return;
        }
      }
      endHandlePacket();
      return;
    } else if (flag == WIN) {
      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {
          packTCP datagram;
          uint8_t payloadTCP[0];
          uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

          dbg(TRANSPORT_CHANNEL, "WIN packet arrived, new window size: %u\n",
              msg->window);
          currSock->effectiveWindow = msg->window;

          makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port,
                  WINACK, msg->seq, 0, currSock->effectiveWindow, payloadTCP,
                  0);

          memcpy(payloadIP, (void *)(&datagram), sizeof(packTCP));

          call InternetProtocol.sendMessage(currSock->dest.addr, 10,
                                            PROTOCOL_TCP, payloadIP,
                                            sizeof(packTCP));

          // This line SHOULD not be necessary, but for some reason,
          // slidingWindowAllowSend[i] is false even when it should be true.
          // I have no idea why.
          slidingWindowAllowSend[i] = TRUE;

          sendData(i);
          endHandlePacket();
          return;
        }
      }
      endHandlePacket();
      return;
    } else if (flag == WINACK) {
      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
        socket_store_t *currSock = &socketList[i];
        if (currSock->src == destPort && currSock->dest.port == srcPort &&
            currSock->dest.addr == srcAddr && currSock->bound &&
            currSock->state != LISTEN) {

          removeTimestamp(i, WIN, msg->ack, 0);
          endHandlePacket();
          return;
        }
      }
      endHandlePacket();
      return;
    }

    endHandlePacket();
    return;
  }

  void endHandlePacket() {
    if (call PacketBuffer.isEmpty()) {
      // If there are no more packets in buffer
      handlingPacket = FALSE;
    } else {
      // If there are still packets, repost the task
      post handlePacket();
    }
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

    if (call PacketBuffer.maxSize() <= call PacketBuffer.size()) {
      // PacketBuffer is full
      return FAIL;
    }

    call PacketBuffer.pushback(msg);

    if (!handlingPacket) {
      // Only post another handlePacket task if it is not already posted
      post handlePacket();
    }

    return SUCCESS;
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
                                  uint16_t bufflen) {
    socket_store_t *currSock;
    uint16_t trueBuffLen = bufflen;
    uint8_t nextRead;
    uint8_t nextRcvd;
    uint8_t *rcvdBuff;
    bool sendWindowPacket = FALSE;

    uint16_t i;
    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return 0;
    }

    currSock = &socketList[fd];
    nextRead = currSock->nextRead;
    nextRcvd = currSock->nextRcvd;

    if (!(currSock->bound) || currSock->state != ESTABLISHED ||
        currSock->flag == NO_RCVD_DATA) {
      // socket has to be bound and already established and have data
      return 0;
    }

    if (bufflen >= SOCKET_BUFFER_SIZE) {
      // cap the buff len
      trueBuffLen = SOCKET_BUFFER_SIZE - 1;
      currSock->flag = NO_RCVD_DATA;
    }

    if ((nextRcvd + 1) % SOCKET_BUFFER_SIZE == nextRead) {
      // This means the read buffer is completely full, so we need to send the
      // client a WIN packet notifying the window size has changed
      sendWindowPacket = TRUE;
    }

    if (nextRcvd > nextRead && nextRead + trueBuffLen >= nextRcvd) {

      uint8_t overflow = nextRead + trueBuffLen - nextRcvd;
      trueBuffLen = trueBuffLen - overflow;
      currSock->flag = NO_RCVD_DATA;

    } else if (nextRcvd < nextRead &&
               nextRead + trueBuffLen >= SOCKET_BUFFER_SIZE &&
               (nextRead + trueBuffLen) % SOCKET_BUFFER_SIZE >= nextRcvd) {
      // If the end index starts lower than the start (wrap around) but ends
      // up greater due to overflow
      uint16_t overflow =
          ((nextRead + trueBuffLen) % SOCKET_BUFFER_SIZE) - nextRcvd;
      trueBuffLen = trueBuffLen - overflow;
      currSock->flag = NO_RCVD_DATA;
    }

    rcvdBuff = currSock->rcvdBuff;
    for (i = 0; i < trueBuffLen; i++) {
      buff[i] = rcvdBuff[(nextRead + i) % SOCKET_BUFFER_SIZE];
    }

    currSock->nextRead =
        (currSock->nextRead + trueBuffLen) % SOCKET_BUFFER_SIZE;
    currSock->effectiveWindow = currSock->effectiveWindow + trueBuffLen;

    if (sendWindowPacket) {
      packTCP datagram;
      uint8_t payloadTCP[0];
      uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

      makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port, WIN,
              0, currSock->nextSend, currSock->effectiveWindow, payloadTCP, 0);

      memcpy(payloadIP, (void *)(&datagram), sizeof(packTCP));

      call InternetProtocol.sendMessage(currSock->dest.addr, 10, PROTOCOL_TCP,
                                        payloadIP, sizeof(packTCP));

      createTimestamp(fd, WIN, currSock->nextSend, 0);
    }

    return trueBuffLen;
  }

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
      // Create a SYN packet with no payload and send it to the dest addr
      // and port
      packTCP msg;
      // Given that this is a SYN packet, most fields (like window) don't
      // matter
      uint8_t flag = SYN;
      // Randomize initial sequence number
      uint8_t initialSeq = call Random.rand16() % SOCKET_BUFFER_SIZE;
      // uint8_t initialSeq = 0;
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
      socket->nextSend = initialSeq;
      socket->nextWritten = initialSeq;
      socket->nextAck = initialSeq;

      socket->state = SYN_SENT;

      createTimestamp(fd, SYN, initialSeq, 0);
      if (!(call PacketTimeout.isRunning())) {
        call PacketTimeout.startOneShot(TIMEOUT_TIMER);
      }

      return SUCCESS;
    }
  }

  event void WaitClose.fired() {
    socket_t fd = call ClosingQueue.popfront();
    socket_store_t *currSock = &(socketList[fd]);
    dbg(TRANSPORT_CHANNEL, "Socket %u is closing.\n", fd);

    // Waits for a while before setting the socket to close.
    currSock->state = CLOSED;
    currSock->bound = FALSE;
    currSock->flag = UNINIT;
    currSock->src = 0;
    currSock->dest.port = 0;
    currSock->dest.addr = 0;

    currSock->nextWritten = 0;
    currSock->nextAck = 0;
    currSock->nextSend = 0;
    currSock->nextRead = 0;
    currSock->nextRcvd = 0;
    currSock->nextExpected = 0;

    currSock->RTT = 0;
    currSock->effectiveWindow = SOCKET_BUFFER_SIZE;

    memset(currSock->sendBuff, 0, SOCKET_BUFFER_SIZE);
    memset(currSock->rcvdBuff, 0, SOCKET_BUFFER_SIZE);

    removeAllTimestamps(fd);

    printSockets();

    if (call ClosingQueue.size() > 0) {
      // If there are other sockets in the queue to be closed
      call WaitClose.startOneShot(CLOSE_WAIT_TIME);
    }
  }

  command uint8_t Transport.getSocketFD(uint8_t destAddr, uint8_t srcPort,
                                        uint8_t destPort) {
    uint16_t i;

    for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
      if (socketList[i].bound) {
        socket_store_t sock = socketList[i];

        if (sock.src == srcPort && sock.dest.port == destPort &&
            sock.dest.addr == destAddr &&
            !(sock.state == CLOSED || sock.state == SYN_RCVD ||
              sock.state == SYN_SENT || sock.state == LISTEN)) {
          return i;
        }
      }
    }

    dbg(TRANSPORT_CHANNEL, "Socket not found!\n");
    dbg(TRANSPORT_CHANNEL, "destAddr: %u | srcPort: %u | destPort: %u\n",
        destAddr, srcPort, destPort);

    return NULL_SOCKET;
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
  command error_t Transport.close(socket_t fd) {
    socket_store_t *currSock;
    packTCP datagram;
    uint16_t sizeTCP = sizeof(packTCP);
    uint8_t payloadTCP[0];
    uint8_t payloadIP[PACKET_MAX_PAYLOAD_SIZE];

    if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) {
      return FAIL;
    }

    currSock = &socketList[fd];

    if (!(currSock->bound) || currSock->state == CLOSED) {
      // socket has to be bound and already established and have room
      return FAIL;
    }
    if (!(currSock->flag == NO_SEND_DATA || currSock->flag == NO_RCVD_DATA)) {
      // If there is still data in the buffers, can't close
      return FAIL;
    }

    if (currSock->state != CLOSE_WAIT) {
      currSock->state = FIN_WAIT_1;
    }

    /*
    void makeTCP(packTCP * Package, uint8_t srcAddr, uint8_t srcPort,
              uint8_t destPort, uint8_t flag, uint8_t ack, uint8_t seq,
              uint8_t window, uint8_t * payload, uint8_t length)
    */
    makeTCP(&datagram, TOS_NODE_ID, currSock->src, currSock->dest.port, FIN,
            currSock->nextExpected, currSock->nextSend, 0, payloadTCP, 0);

    memcpy(payloadIP, (void *)(&datagram), sizeTCP);

    call InternetProtocol.sendMessage(currSock->dest.addr, 10, PROTOCOL_TCP,
                                      payloadIP, sizeTCP);

    createTimestamp(fd, FIN, currSock->nextSend, 0);

    return SUCCESS;
  }

  /**
   * A hard close, which is not graceful. This portion is optional.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t Transport.release(socket_t fd) { return FAIL; }

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
