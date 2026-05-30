{ pkgs ? import <nixpkgs> {}
, stdenv
, zig
}:
stdenv.mkDerivation {
  pname = "minx-fileserver";
  version = "0.0.1";
  nativeBuildInputs = [ zig.hook ]
}
