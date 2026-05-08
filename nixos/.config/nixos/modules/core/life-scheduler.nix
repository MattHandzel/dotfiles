{ inputs, ... }: {
  imports = [
    inputs.life-scheduler.nixosModules.default
  ];
}
