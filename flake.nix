{
  description = "Minx file server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, naersk, ... }:
    let
      overlay = final: prev:
        let naersk' = final.callPackage naersk {}; in
        naersk'.buildPackage {
          src = ./.;
        };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = overlay pkgs pkgs;
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.rustc
            pkgs.cargo
            pkgs.clippy
            pkgs.rust-analyzer
            pkgs.rustfmt
          ];
        };
      }
    ) // {
      overlays.default = overlay;
    };
}
