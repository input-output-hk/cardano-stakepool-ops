{
  outputs = { ... }: {
    nixosModules.cardano-node = {
      services.cardano-node = {
        stateDir = "/persist";
        socketPath = "/alloc/node.socket";
      };
    };
    nixosModules.cardano-submit-api = {
      services.cardano-submit-api = {
        listenAddress = "0.0.0.0";
        socketPath = "/alloc/node.socket";
      };
    };
  };
}
