# modules/system/base.nix

{ config, lib, pkgs, ... }:

{
  # Basic system configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Basic networking
  networking = {
    useDHCP = true;
    firewall = {
      enable = true;
      # No ports opened by default - services should declare their own
    };
  };

  # Essential system packages
  environment.systemPackages = with pkgs; [
    # System utilities
    wget
    curl
    vim
    git
    htop
    tmux
    
    # Networking tools
    inetutils
    netcat
    dig
    
    # Docker requirements
    docker-compose

    # Monitoring
    bottom # Better system monitor
    ctop   # Container monitoring
  ];

  # Basic system services
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # For testing only
      PermitRootLogin = "prohibit-password";
      X11Forwarding = false;
    };
  };

  # Resource monitoring service
  systemd.services.resource-monitor = {
    description = "System Resource Monitor";
    script = ''
      memory_total=$(free -m | awk '/^Mem:/{print $2}')
      if [ "$memory_total" -lt 2048 ]; then
        echo "Warning: System has less than 2GB RAM (${memory_total}MB)"
        exit 1
      fi
      
      # Check disk space
      disk_free=$(df -m /var/lib | awk 'NR==2 {print $4}')
      if [ "$disk_free" -lt 5120 ]; then
        echo "Warning: Less than 5GB free space available"
        exit 1
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Docker base configuration
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = []; # Add your SSH keys here
    initialPassword = "changeme";
  };

  # Shell configuration
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "docker" "docker-compose" ];
      theme = "robbyrussell";
    };
  };
  users.defaultUserShell = pkgs.zsh;

  # System limits for Docker
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "fs.inotify.max_user_watches" = 524288;
    "net.core.somaxconn" = 65535;
  };
}