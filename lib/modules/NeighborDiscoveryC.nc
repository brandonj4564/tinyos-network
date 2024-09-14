configuration NeighborDiscoveryC { provides interface NeighborDiscovery; }

implementation {
  components NeighborDiscoveryP;
  NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;
}