# modules/system/base.nix

{ config, lib, pkgs, ... }:

{
  # Basic networking configuration
  networking = {
    hostName = "nixos-manager";  # You can override this in specific configs
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22    # SSH
      ];
      allowedUDPPorts = [ 
        config.services.tailscale.port
      ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  # Essential system packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    wget vim git curl
    
    # Network tools
    tailscale
    bind        # for dig/nslookup
    inetutils   # for ping, etc.
    
    # System monitoring
    htop tmux
    
    # Shell
    zsh oh-my-zsh

    # Docker requirements
    docker-compose
    ctop
  ];

  # Enable Tailscale
  services.tailscale.enable = true;

  # SSH Configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # Will be disabled after initial setup
      PermitRootLogin = "yes";       # Will be disabled after initial setup
      X11Forwarding = false;
      PermitEmptyPasswords = false;
      MaxAuthTries = 3;
    };
  };

  # User Configuration
  users.users.admin = {
    isNormalUser = true;
    description = "Management Admin";
    extraGroups = [ "wheel" "docker" ];
    initialPassword = "changeme";
  };

  # Shell Configuration
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "docker" "sudo" ];
      theme = "robbyrussell";
    };
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;

  # Docker base configuration
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # System limits for Docker
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "fs.inotify.max_user_watches" = 524288;
    "net.core.somaxconn" = 65535;
  };
}