{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./tests/twenty-test.nix
  ];
}