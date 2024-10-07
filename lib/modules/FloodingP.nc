
/*
TODO:
1. Create a sequence variable here that starts at 0 and increments every time a
new packet is sent
2. Add a node table (probably with the hashmap structure) that tracks the
highest sequence packet received from each node
3. Create the floodSend() function that broadcasts to every node. This should be
a generic function that takes in a Destination and Payload argument.
4. Create a floodReceive() function that is called when a node receives a packet
with the flooding protocol. It will decrement the TTL and forward the packet if
it is not the destination.
5. Each node checks if the packet has a higher sequence number using the node
table. We are not using neighbor discovery in flooding, probably. If the packet
has an equal or lower sequence, drop it.
*/

module FloodingP {
  provides interface Flooding;
  uses interface Hashmap<uint16_t> as NodeTable;

  uses interface SimpleSend;

  uses interface Timer<TMilli> as CacheReset;
}

implementation {
  uint16_t sequenceNum = 0;

  void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL,
                uint16_t protocol, uint16_t seq, uint8_t * payload,
                uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
  }

  command void Flooding.start() {
    // Test function, only sends a flooding packet from one node
    if (TOS_NODE_ID == 8) {
      uint8_t payload[1] = {0};
      call Flooding.sendMessage(1, 10, payload, sizeof(payload));

      call CacheReset.startPeriodic(200000);
    }
  }

  event void CacheReset.fired() {
    // Reset the soft state of the cache occasionally
    // Ensures that, if a node dies, it can still send messages later by
    // forgetting previously high sequences

    uint32_t *tableKeys = (uint32_t *)(call NodeTable.getKeys());
    uint16_t tableSize = call NodeTable.size();
    uint16_t i;

    // dbg(FLOODING_CHANNEL, "FLOODING: Clearing cache...\n");

    for (i = 0; i < tableSize; i++) {
      uint32_t key = tableKeys[i];
      call NodeTable.remove(key);
    }
    // God I hope this doesn't have concurrency issues
  }

  command void Flooding.sendMessage(uint16_t dest, uint16_t TTL,
                                    uint8_t * payload, uint8_t length) {
    pack message;
    makePack(&message, TOS_NODE_ID, dest, TTL, PROTOCOL_FLOODING, sequenceNum,
             payload, length);
    sequenceNum++;

    dbg(FLOODING_CHANNEL, "FLOODING: Message sent to %i.\n", dest);
    call SimpleSend.send(message, AM_BROADCAST_ADDR);
  }

  command void Flooding.floodMessage(uint16_t TTL, uint8_t * payload,
                                     uint8_t length) {
    // This command is different from sendMessage because sendMessage sends to
    // one specific node, while floodMessage floods to everybody in the network.
    // Necessary for informing the network of a node's neighbors

    pack message;
    makePack(&message, TOS_NODE_ID, AM_BROADCAST_ADDR, TTL,
             PROTOCOL_FLOODING_ALL, sequenceNum, payload, length);
    sequenceNum++;

    dbg(FLOODING_CHANNEL, "FLOODING: Message flooded to network.\n");
    call SimpleSend.send(message, AM_BROADCAST_ADDR);
  }

  command void Flooding.recieveMessage(pack * msg) {
    uint16_t dest = msg->dest;
    uint16_t src = msg->src;

    // If this node is not the destination
    if (dest != TOS_NODE_ID) {

      // Check TTL and whether or not the current node is the original source
      if (msg->TTL > 0 && src != TOS_NODE_ID) {
        // Check with the node table if the sequence is higher than previously
        // seen
        if (call NodeTable.contains(src)) {
          uint16_t highestSeq = call NodeTable.get(src);

          // If the seq of the message is higher than previously seen, forward
          if (msg->seq > highestSeq) {
            call NodeTable.remove(src);
            call NodeTable.insert(src, msg->seq);
            msg->TTL = msg->TTL - 1; // Reduce TTL

            call SimpleSend.send(*msg, AM_BROADCAST_ADDR);
          } else {
            // dbg(FLOODING_CHANNEL, "FLOODING: Dropped packet.\n");
          }
        } else {
          // Hasn't received any messages from the src node yet so NodeTable
          // contains no records

          // dbg(FLOODING_CHANNEL, "FLOODING: First time received packet.\n");
          // dbg(FLOODING_CHANNEL, "FLOODING: Flooding message, destination
          // %i.\n",
          //     dest);

          call NodeTable.insert(src, msg->seq);
          msg->TTL = msg->TTL - 1; // Reduce TTL

          call SimpleSend.send(*msg, AM_BROADCAST_ADDR);
        }
      } else {
        // dbg(FLOODING_CHANNEL, "FLOODING: Dropped packet.\n");
      }
    } else {
      // Message reached destination
      dbg(FLOODING_CHANNEL,
          "FLOODING: FINALLY REACHED DESTINATION, SENT FROM %i\n", src);
    }
  }
}
