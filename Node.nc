/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "includes/CommandMsg.h"
#include "includes/channels.h"
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/sendInfo.h"
#include <Timer.h>

module Node {
  uses interface Boot;

  uses interface SplitControl as AMControl;
  uses interface Receive;

  uses interface SimpleSend as Sender;

  uses interface CommandHandler;

  // Project 1
  uses interface NeighborDiscovery;
  uses interface Flooding;

  // Project 2
  uses interface LinkState;
  uses interface InternetProtocol;

  // Project 3
  uses interface Transport;
  uses interface Timer<TMilli> as ClientTimer;
  uses interface Timer<TMilli> as TestTimer;
}

implementation {
  pack sendPackage;

  // used for project 3
  uint8_t transferData;
  uint16_t dataSent;
  socket_t currSock;

  // Prototypes
  void makePack(pack * Package, uint8_t src, uint8_t dest, uint8_t TTL,
                uint8_t protocol, uint8_t seq, uint8_t * payload,
                uint8_t length);

  event void Boot.booted() {
    call AMControl.start();

    dbg(GENERAL_CHANNEL, "Booted\n");

    call Flooding.start();
  }

  event void AMControl.startDone(error_t err) {
    if (err == SUCCESS) {
      dbg(GENERAL_CHANNEL, "Radio On\n");
    } else {
      // Retry until successful
      call AMControl.start();
    }
  }

  event void AMControl.stopDone(error_t err) {}

  event message_t *Receive.receive(message_t * msg, void *payload,
                                   uint8_t len) {
    // dbg(GENERAL_CHANNEL, "Packet Received\n");

    if (len == sizeof(pack)) {
      pack *myMsg = (pack *)payload;
      uint16_t prtcl = myMsg->protocol;

      if (prtcl == PROTOCOL_BEACON) {
        call NeighborDiscovery.beaconSentReceived(myMsg);
      } else if (prtcl == PROTOCOL_BEACONREPLY) {
        call NeighborDiscovery.beaconResponseReceived(myMsg);
      } else if (prtcl == PROTOCOL_FLOODING || prtcl == PROTOCOL_LINKSTATE) {
        call Flooding.receiveMessage(myMsg);
      } else if (prtcl == PROTOCOL_IP) {
        call InternetProtocol.receiveMessage(myMsg);
      } else {
        dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
      }
      return msg;
    }

    dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
    return msg;
  }

  event void CommandHandler.ping(uint16_t destination, uint8_t * payload) {
    dbg(GENERAL_CHANNEL, "PING EVENT \n");
    makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload,
             PACKET_MAX_PAYLOAD_SIZE);
    // call Sender.send(sendPackage, destination);

    call InternetProtocol.sendMessage(destination, 10, PROTOCOL_PING, payload,
                                      PACKET_MAX_PAYLOAD_SIZE);
  }

  event void CommandHandler.printNeighbors() {
    uint32_t *neighborList =
        (uint32_t *)(call NeighborDiscovery.getNeighbors());
    uint32_t size = call NeighborDiscovery.getNumNeighbors();

    int i;
    for (i = 0; i < size; i++) {
      dbg(GENERAL_CHANNEL, "Neighbors: %i\n", neighborList[i]);
    }
  }

  event void NeighborDiscovery.listUpdated() {
    // dbg(GENERAL_CHANNEL, "the neighborlist is updated\n");
  }

  event void CommandHandler.printRouteTable() {
    int numRoutes = call LinkState.getNumActiveRoutes();
    int routes[numRoutes];
    int i;
    call LinkState.getActiveRoutes(routes); // Assigns routes

    dbg(GENERAL_CHANNEL, "Printing routing table, if a node is not "
                         "printed then it does not have a valid route.\n");

    for (i = 0; i < numRoutes; i++) {
      int node = routes[i];
      dbg(GENERAL_CHANNEL,
          "Dest: %i | Next Hop: %i | Cost %i | Backup Hop: %i | Backup Cost: "
          "%i\n",
          node, call LinkState.getNextHop(node, 0),
          call LinkState.getCost(node, 0), call LinkState.getNextHop(node, 1),
          call LinkState.getCost(node, 1));
    }
  }

  event void CommandHandler.printLinkState() {
    dbg(GENERAL_CHANNEL, "Printing out all LSAs stored in this node.\n");
    call LinkState.printAllLSA();
  }

  event void CommandHandler.printDistanceVector() {}

  /**
   * --------------------- TRANSPORT PROJECT 3 SECTION ---------------------
   */

  event void Transport.newConnectionReceived(socket_t fd) {
    dbg(GENERAL_CHANNEL, "New connection received!\n");
    call Transport.accept(fd);
  }

  event void TestTimer.fired() {
    uint8_t size = 100;
    uint8_t data[size];
    uint8_t actualSize;
    uint8_t i;

    actualSize = call Transport.read(currSock, data, size);
    dbg(GENERAL_CHANNEL, "Reading %u bytes of data from socket %u.\n",
        actualSize, currSock);
    for (i = 0; i < actualSize; i++) {
      dbg(GENERAL_CHANNEL, "%u\n", data[i]);
    }
  }

  event void Transport.dataAvailable(socket_t fd) {
    uint8_t size = 100;
    uint8_t data[size];
    uint8_t actualSize;
    uint8_t i;

    actualSize = call Transport.read(fd, data, size);
    dbg(GENERAL_CHANNEL, "Reading %u bytes of data from socket %u.\n",
        actualSize, fd);
    for (i = 0; i < actualSize; i++) {
      dbg(GENERAL_CHANNEL, "%u\n", data[i]);
    }

    // currSock = fd;
    // call TestTimer.startOneShot(500);
  }

  event void CommandHandler.setTestServer(uint8_t port) {
    // Initiates the server at this node with some port that listens for
    // connections
    socket_t fd = call Transport.socket();
    socket_addr_t addr;
    error_t outcome;
    addr.port = port;
    addr.addr = TOS_NODE_ID;
    dbg(GENERAL_CHANNEL, "Initializing listener socket with port %u\n", port);

    outcome = call Transport.bind(fd, &addr);

    // I didn't implement the part where it starts a timer to accept connections
    if (outcome == FAIL) {
      dbg(GENERAL_CHANNEL, "Something went wrong creating a port...\n");
    }

    call Transport.listen(fd);
  }

  event void CommandHandler.closeClient(uint8_t destAddr, uint8_t srcPort,
                                        uint8_t destPort) {
    socket_t fileDescriptor;
    error_t outcome;

    dbg(GENERAL_CHANNEL,
        "Close client command issued, attempting to close socket.\n");

    fileDescriptor = call Transport.getSocketFD(destAddr, srcPort, destPort);
    outcome = call Transport.close(fileDescriptor);

    if (outcome == FAIL) {
      // Still data left, set a timer
      call ClientTimer.startOneShot(500);
      currSock = fileDescriptor;
    }
  }

  event void Transport.connectionSuccess(socket_t fd) {
    // socket fd's connection to server is a success
    // time to start writing data
    uint8_t data[transferData];
    uint16_t i;

    for (i = 0; i < transferData; i++) {
      data[i] = (uint8_t)i;
    }

    dbg(GENERAL_CHANNEL, "Socket %u succesfully connected!\n", fd);
    dataSent = call Transport.write(fd, data, transferData);
  }

  event void Transport.bufferFreed(socket_t fd) {
    if (dataSent < transferData) {
      uint8_t data[transferData - dataSent];
      uint16_t i;

      for (i = 0; i < transferData - dataSent; i++) {
        data[i] = (uint8_t)(i + dataSent);
      }
      dbg(GENERAL_CHANNEL, "Socket %u has more space in sendBuffer.\n", fd);

      dataSent =
          dataSent + call Transport.write(fd, data, transferData - dataSent);

      // if (transferData - dataSent <= 0) {
      //   // No more data to be sent, close the connection

      //   error_t outcome = call Transport.close(fd);
      //   dbg(GENERAL_CHANNEL, "Trying to close socket %u...\n", fd);

      //   if (outcome == FAIL) {
      //     // Still data left, set a timer
      //     call ClientTimer.startOneShot(500);
      //     currSock = fd;
      //   }
      // }
    }
  }

  event void Transport.alertClose(socket_t fd) {
    error_t outcome = call Transport.close(fd);
    currSock = fd;

    if (outcome == FAIL) {
      // Still data left, set a timer
      dbg(GENERAL_CHANNEL, "Trying to close socket %u...\n", currSock);
      call ClientTimer.startOneShot(500);
    } else if (outcome == SUCCESS) {
      dbg(GENERAL_CHANNEL, "Successfully called close() on socket %u!\n",
          currSock);
    }
  }

  event void ClientTimer.fired() {
    error_t outcome = call Transport.close(currSock);
    if (outcome == FAIL) {
      // Still data left, set a timer
      dbg(GENERAL_CHANNEL, "Trying to close socket %u...\n", currSock);
      call ClientTimer.startOneShot(500);
    } else if (outcome == SUCCESS) {
      dbg(GENERAL_CHANNEL, "Successfully called close() on socket %u!\n",
          currSock);
    }
  }

  event void CommandHandler.setTestClient(uint8_t destAddr, uint8_t srcPort,
                                          uint8_t destPort, uint8_t transfer) {
    // TODO: Implement these actually according to the doc
    socket_t fd = call Transport.socket();
    socket_addr_t clientAddr;
    socket_addr_t serverAddr;
    error_t outcome;
    transferData = transfer;

    dbg(GENERAL_CHANNEL, "Initializing client socket with port %u\n", srcPort);

    clientAddr.port = srcPort;
    clientAddr.addr = TOS_NODE_ID;
    serverAddr.port = destPort;
    serverAddr.addr = destAddr;

    outcome = call Transport.bind(fd, &clientAddr);
    if (outcome == FAIL) {
      dbg(GENERAL_CHANNEL, "setTestClient binding client socket failed...\n");
      return;
    }

    outcome = call Transport.connect(fd, &serverAddr);
    if (outcome == FAIL) {
      dbg(GENERAL_CHANNEL, "setTestClient connecting to server failed...\n");
      return;
    }
  }

  /**
   * --------------------- END TRANSPORT PROJECT 3 SECTION ---------------------
   */

  event void CommandHandler.setAppServer() {}

  event void CommandHandler.setAppClient() {}

  void makePack(pack * Package, uint8_t src, uint8_t dest, uint8_t TTL,
                uint8_t protocol, uint8_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }
}
