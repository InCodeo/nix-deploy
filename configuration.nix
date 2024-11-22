{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking configuration
  networking = {
    hostName = "nixos-manager";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22    # SSH
        53    # DNS (AdGuard)
        80    # HTTP (NPM)
        81    # NPM Admin Portal
        443   # HTTPS (NPM)
        3000  # AdGuard Home Admin
        3150  # Homepage Dashboard
        3306  # MariaDB
        8000  # Test HTTP Server
        9000  # Portainer
      ];
      allowedUDPPorts = [ 
        config.services.tailscale.port
        53    # DNS
      ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  # Docker and Container Configuration
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      package = pkgs.docker;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      
    };
    oci-containers = {
      backend = "docker";
      containers = {
        portainer = {
          image = "portainer/portainer-ce:latest";
          volumes = [
            "/var/run/docker.sock:/var/run/docker.sock"
            "/var/lib/portainer/data:/data"
          ];
          environment = {
            TZ = "Australia/Sydney";
          };
          ports = ["9000:9000"];
          autoStart = true;
        };
        
        homepage = {
          image = "ghcr.io/gethomepage/homepage:latest";
          ports = [ "3150:3000" ];
          environment = {
            PUID = "1000";
            PGID = "1000";
            DEBUG = "true";
          };
          volumes = [
            "/var/lib/homepage/config:/app/config"
            "/var/run/docker.sock:/var/run/docker.sock:ro"
          ];
          autoStart = true;
        };
      };
    };
  };

  # AdGuard Home configuration
  services.adguardhome = {
    enable = true;
    host = "0.0.0.0";
    port = 3000;
    mutableSettings = false;
    
    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        bootstrap_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
        upstream_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
        local_domain_name = "home";
        resolve_clients = true;
        rewrites = [
        {
          domain = "my.home";
          answer = "100.113.131.93";
        }
      ];
      };
      http = {
        username = "admin";
        password = ""; # Add your password hash here
      };
      filters = [];
      user_rules = [];
      schema_version = 12;
    };
  };

  # Directory Structure
  systemd.tmpfiles.rules = [
    "d /var/lib/portainer 0750 admin docker -"
    "d /var/lib/portainer/data 0750 admin docker -"
    "d /var/lib/npm 0750 admin docker -"
    "d /var/lib/npm/data 0750 admin docker -"
    "d /var/lib/npm/mysql 0750 admin docker -"
    "d /var/lib/npm/letsencrypt 0750 admin docker -"
    "d /var/lib/www/test 0755 admin admin -"
    "d /var/lib/homepage 0755 admin docker -"
    "d /var/lib/homepage/config 0755 admin docker -"
  ];

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
    shellInit = ''
      ${builtins.replaceStrings ["\r\n"] ["\n"] (builtins.readFile ./functions.zsh)}
      ${builtins.replaceStrings ["\r\n"] ["\n"] (builtins.readFile ./client-functions.zsh)}
    '';
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;

  # System Packages
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

    # Added for test server
    python3
  ];

  # Enable Tailscale
  services.tailscale.enable = true;

  # Kernel Parameters
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "fs.inotify.max_user_watches" = 524288;
    "net.core.somaxconn" = 65535;
  };

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

  system.stateVersion = "24.05";
}