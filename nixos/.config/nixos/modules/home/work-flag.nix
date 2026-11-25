# One switch, `my.work`, that the shared modules read to leave out anything
# that talks to Matt's personal server or accounts. Only the Redwood-issued
# laptop's profile (./work.nix) turns it on; every other host keeps the default.
{lib, ...}: {
  options.my.work = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "True on an employer-managed machine: no personal servers, accounts or tools.";
  };
}
