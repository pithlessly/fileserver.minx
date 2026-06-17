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
        let
          naersk' = final.callPackage naersk {};
          bin_derivation = naersk'.buildPackage {
            src = ./.;
          };
        in
        {
          minx-fileserver =
            final.symlinkJoin {
              meta.mainProgram = "minx_fileserver";
              name = "minx-fileserver";
              paths = [ bin_derivation ]; # provides /bin
              postBuild = ''
                mkdir $out/share
                cp -r ${./templates} $out/share/templates
                cp -r ${./static} $out/share/static
              '';
            };
        };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = (overlay pkgs pkgs).minx-fileserver;
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
