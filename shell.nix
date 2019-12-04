let
  pkgs = import (fetchTarball  https://nixos.org/channels/nixos-19.09/nixexprs.tar.xz) {};
  pkgsGeth = import (fetchTarball  https://nixos.org/channels/nixos-19.03/nixexprs.tar.xz) {};
  # pkgsUnstable = import (fetchTarball https://github.com/NixOS/nixpkgs-channels/archive/nixos-unstable.tar.gz ) {};
in with pkgs;
pkgs.stdenv.mkDerivation {
  name = "omisego-chain-dev";
  buildInputs = [
    rebar3
    elixir_1_8
    beamPackages.hex
    # erocksdb below
    rocksdb
    cmake
    # solc below
    solc
    # libsecp256k1 below
    autoconf
    automake
    libtool
    gmp
    secp256k1
    # used to download some of the dependencies
    git
    # used while building prod release
    openssl
    # runtime dependencies
    pkgsGeth.go-ethereum
  ];
  propagateBuildInputs = [
    # rocksdb
    # patchelf
  ];
  CMAKE_PREFIX_PATH = "${rocksdb}";
}
