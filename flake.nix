{
  description = "Minx file server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # zig = {
    #   url = "github:mitchellh/zig-overlay";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-utils.follows = "flake-utils";
    # };

    # zls = {
    #   url = "github:zigtools/zls/0.14.0";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.zig-overlay.follows = "zig";
    # };
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
  flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      # zig = inputs.zig.packages.${system}."0.14.1";
      # zls = inputs.zls.packages.${system}.default.overrideAttrs {
      #   nativeBuildInputs = [ zig ];
      # };
      minx-fileserver = pkgs.callPackage ./default.nix {
        # inherit zig;
      };
    in
    {
      packages.minx-fileserver = minx-fileserver;
      packages.default = minx-fileserver;
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.zig
          pkgs.zls
          pkgs.zon2nix
        ];
        buildInputs = [
          pkgs.pandoc
        ];
      };
    }
  );
}
