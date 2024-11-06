#include "../../includes/socket.h"
#include "../../packet.h"

module TransportP { 
  provides interface Transport; 

  uses interface Boot;
}

implementation {
  typedef nx_struct structTCP {
    nx_uint8_t src;
    nx_uint8_t dest;
    nx_uint8_t seq; 
    nx_uint8_t ack;
    nx_uint8_t flag;
    nx_uint8_t adWindow;
    nx_uint8_t payload[0];
  }
  structTCP;

  socket_store_t socketList[MAX_NUM_OF_SOCKETS]; 
  // currentSocket is used to index socketList
  uint8_t currentSocket = 0;

  event void Boot.booted() {
    uint8_t i;
    for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
      // Initialize all sockets as being free and with default values
      socketList[i].state = CLOSED;   
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
      
      socketList[i] = 0;
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
  command socket_t TransportP.socket() {
    // Have a list of available sockets and return one of them i guess
    socket_t sock;
    uint8_t counter = 0; // Prevent infinite loops if no sockets are available

    while(){
      // TODO: Change this
      if(socketList[currentSocket % MAX_NUM_OF_SOCKETS] == 0){
        // socket_t is just a reskinned uint8_t anyways so it's fine to typecast
        sock = (socket_t) (currentSocket % MAX_NUM_OF_SOCKETS);
        currentSocket++;
        return sock;
      }

      currentSocket++;
      counter++;

      if(counter > MAX_NUM_OF_SOCKETS){
        // No available sockets, looped around too many times
        return NULL;
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
  command error_t TransportP.bind(socket_t fd, socket_addr_t * addr) {
    // Perhaps this could be as simple as setting addr->port = fd?
    // error_t: 0 = success, 1 = failure
    
    // Is the address the node we are setting up a connection too? or the node we are in
    //       If its node we are connecting too we could have an array to store it 
    //          0    1    2 ...... fd/sockets
    //         addr addr addr ...... address we are connecting too 
    error_t result = 0;
    return result;
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
  command socket_t TransportP.accept(socket_t fd) {
    // There is a queue of incoming connections. This command should accept the first connection
    // in the queue, create a new connected socket, and return the file descriptor for that socket.
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
  command uint16_t TransportP.write(socket_t fd, uint8_t * buff,
                                    uint16_t bufflen) {}

  /**
   * This will pass the packet so you can handle it internally.
   * @param
   *    pack *package: the TCP packet that you are handling.
   * @Side Client/Server
   * @return uint16_t - return SUCCESS if you are able to handle this
   *    packet or FAIL if there are errors.
   */
  command error_t TransportP.receive(pack * package) {}

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
  command uint16_t TransportP.read(socket_t fd, uint8_t * buff,
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
  command error_t TransportP.connect(socket_t fd, socket_addr_t * addr) {}

  /**
   * Closes the socket.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t TransportP.close(socket_t fd) {}

  /**
   * A hard close, which is not graceful. This portion is optional.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t TransportP.release(socket_t fd) {}

  /**
   * Listen to the socket and wait for a connection.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Server
   * @return error_t - returns SUCCESS if you are able change the state
   *   to listen else FAIL.
   */
  command error_t TransportP.listen(socket_t fd) {}
}
