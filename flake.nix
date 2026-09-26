{
  description = "Pinned deploy artifacts for dgramop-dedi. Bump lock here instead of the systems flake.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";

    rg552-nixos-main.url = "github:dgramop/rg552-nixos/main";
    rg552-nixos-main.inputs.nixpkgs.follows = "nixpkgs";

    rg552-nixos-stable.url = "github:dgramop/rg552-nixos/stable";
    rg552-nixos-stable.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    system = "aarch64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # The manifest of live versions on dedi. Keys become paths inside the
    # deployed profile (e.g. /nix/var/nix/profiles/dgramop-releases/rg552-sd/main).
    # To add a version: declare a new input above pinning the ref/tag/rev you
    # want, then add an entry here. `nix flake lock --update-input <name>` moves
    # a pointer without disturbing the others.
    manifest = {
      "rg552-sd/main"   = inputs.rg552-nixos-main.packages.${system}.default;
      "rg552-sd/stable" = inputs.rg552-nixos-stable.packages.${system}.default;
    };
  in {
    packages.${system} = {
      default = pkgs.linkFarm "dgramop-releases" (
        pkgs.lib.mapAttrsToList (name: path: { inherit name path; }) manifest
      );

      push-releases = pkgs.writeShellApplication {
        name = "push-releases";
        runtimeInputs = [ pkgs.openssh ];
        text = builtins.readFile ./scripts/push-releases.sh;
      };
    };
  };
}
