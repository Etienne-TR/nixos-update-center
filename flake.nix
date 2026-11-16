{
  description = "Centre de mises à jour NixOS : système, Home Manager et Flatpak, préparés en arrière-plan";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      meta = import ./meta.nix;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      lib = { inherit meta; };

      # Les modules construisent les paquets avec le nixpkgs de la
      # configuration qui les importe (pas de second nixpkgs).
      nixosModules.default = import ./modules/nixos.nix { inherit meta; };
      homeManagerModules.default = import ./modules/home.nix { inherit meta; };

      packages = forAll (pkgs: rec {
        engine = pkgs.callPackage ./engine/package.nix { inherit meta; };
        ui = pkgs.callPackage ./ui/package.nix { inherit meta; };
        default = engine;
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
