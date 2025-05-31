{ pkgs ? import <nixpkgs> {}
, stdenv
, zig_0_14
}:
stdenv.mkDerivation {
  pname = "minx-fileserver";
  version = "0.0.1";
  nativeBuildInputs = [ zig_0_14.hook ]
}
