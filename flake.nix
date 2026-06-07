{
  description = "Minx file server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
  flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
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
  );
}
