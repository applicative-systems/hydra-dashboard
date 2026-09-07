{ lib, ... }:
let
  keys = import ../snakeoil-keys.nix;
in
{
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ keys.public ];

  nix.settings.substituters = lib.mkForce [ ];

  virtualisation.cores = 2;
  virtualisation.memorySize = 1024;
}
