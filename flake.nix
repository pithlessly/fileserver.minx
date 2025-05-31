{
  description = "Minx file server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    zls = {
      url = "github:zigtools/zls/0.14.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig, zls, ... }:
  flake-utils.lib.eachSystem (builtins.attrNames zig.packages) (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      zig_0_14 = zig.packages.${system}."0.14.0";
      zls_0_14 = zls.packages.${system}.default.overrideAttrs {
        nativeBuildInputs = [ zig_0_14 ];
      };
      nativeBuildInputs = [ zig_0_14 ];
      minx-fileserver = pkgs.callPackage ./default.nix { inherit zig_0_14; };
    in
    {
      inherit nativeBuildInputs;
      packages.hello = pkgs.hello;
      packages.default = pkgs.hello;
      devShells.default = pkgs.mkShell {
        buildInputs = nativeBuildInputs ++ [
          zls_0_14
          pkgs.zon2nix
          pkgs.pandoc
        ];
      };
    }
  );
}
