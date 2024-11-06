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
}

implementation {
  pack sendPackage;

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
      } else if (prtcl == PROTOCOL_PING || prtcl == PROTOCOL_PINGREPLY) {
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

  event void CommandHandler.setTestServer() {}

  event void CommandHandler.setTestClient() {}

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
