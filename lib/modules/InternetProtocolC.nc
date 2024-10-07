configuration InternetProtocolC { provides interface InternetProtocol; }

implementation {
  components InternetProtocolP;
  InternetProtocol = InternetProtocolP.InternetProtocol;
}