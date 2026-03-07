{ inputs, ... }: {
  imports = [
    inputs.second-brain-search.nixosModules.default
  ];
}
