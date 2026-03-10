{ inputs, ... }: {
  imports = [
    inputs.text-to-speech-service.nixosModules.default
  ];
}
