{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  # I like to define variables for derivations that have
  # a specific version and are subject to change over time.
  elixir = beam.packages.erlangR22.elixir_1_9;
  libsecp256k1 = secp256k1.secp256k1-2017-12-18;
in

mkShell {
  propagatedBuildInputs = [ elixir git cmake erlangR22 gmp secp256k1 solc ];
}
