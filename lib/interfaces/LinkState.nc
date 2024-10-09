interface LinkState { 
    command void receiveLSA(pack * msg); 
    command void LinkState.sendLSA(pack * msg);
    
}