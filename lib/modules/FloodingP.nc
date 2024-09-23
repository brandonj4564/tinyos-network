
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
    if (TOS_NODE_ID == 8) {
      uint8_t payload[1] = {0};
      call Flooding.sendMessage(1, 10, payload, sizeof(payload));
      dbg(GENERAL_CHANNEL, "Message sent from %i\n", TOS_NODE_ID);
    }
  }

  command void Flooding.sendMessage(uint16_t dest, uint16_t TTL,
                                    uint8_t * payload, uint8_t length) {
    pack message;
    makePack(&message, TOS_NODE_ID, dest, TTL, PROTOCOL_FLOODING, sequenceNum,
             payload, length);
    sequenceNum++;

    call SimpleSend.send(message, AM_BROADCAST_ADDR);
  }

  command void Flooding.recieveMessage(pack * msg) {
    // If this node is not the destination
    uint16_t dest = msg->dest;
    uint16_t src = msg->src;

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
            dbg(GENERAL_CHANNEL, "dropped packet at %i\n", TOS_NODE_ID);
          }
        } else {
          // Hasn't received any messages from the src node yet so NodeTable
          // contains no records
          dbg(GENERAL_CHANNEL, "first time received at %i\n", TOS_NODE_ID);
          call NodeTable.insert(src, msg->seq);
          msg->TTL = msg->TTL - 1; // Reduce TTL

          call SimpleSend.send(*msg, AM_BROADCAST_ADDR);
        }
      }
    } else {
      // Message reached destination
      dbg(GENERAL_CHANNEL, "FINALLY REACHED DESTINATION, SENT FROM %i\n", src);
    }
  }
}