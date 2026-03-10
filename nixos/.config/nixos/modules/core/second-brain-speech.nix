{ inputs, ... }: {
  imports = [
    inputs.second-brain-speech.nixosModules.default
  ];
}
