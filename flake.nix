{
  description = "Pinned deploy artifacts for dgramop-dedi. Bump lock here instead of the systems flake.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";

    rg552-nixos-2026_09_26.url = "github:dgramop/rg552-nixos/releases/2026_09_26";
    rg552-nixos-2026_09_26.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    supportedSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems f;

    # The manifest of live versions on dedi. Keys become paths inside the
    # deployed linkFarm (e.g. /nix/var/nix/gcroots/dgramop-releases/rg552-sd/2026_09_26).
    # Each entry pins to a specific target system — the linkFarm just holds
    # symlinks, so it can be assembled on any host that has (or can substitute)
    # the referenced store paths.
    manifest = {
      "rg552-sd/2026_09_26" = inputs.rg552-nixos-2026_09_26.packages.aarch64-linux.default;
    };
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.linkFarm "dgramop-releases" (
        pkgs.lib.mapAttrsToList (name: path: { inherit name path; }) manifest
      );

      push-releases = pkgs.writeShellApplication {
        name = "push-releases";
        runtimeInputs = [ pkgs.openssh ];
        text = builtins.readFile ./scripts/push-releases.sh;
      };
    });
  };
}
