# modules/docker/twenty.nix

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.twenty;
  
  # Generate a random string for initial setup
  generateSecret = ''
    if [ ! -f /var/lib/twenty/secrets/app_secret ]; then
      mkdir -p /var/lib/twenty/secrets
      ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/lib/twenty/secrets/app_secret
      chmod 600 /var/lib/twenty/secrets/app_secret
      chown -R 1000:1000 /var/lib/twenty/secrets
    fi
  '';

in {
  options.services.twenty = {
    enable = mkEnableOption "Twenty CRM";
    
    port = mkOption {
      type = types.port;
      default = 3333;
      description = "Port for Twenty web interface";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/twenty";
      description = "Directory for Twenty data";
    };

    postgresql = {
      password = mkOption {
        type = types.str;
        description = "PostgreSQL superuser password";
      };
    };
  };

  config = mkIf cfg.enable {
    # Ensure docker is enabled
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 1000 1000 -"
      "d ${cfg.dataDir}/postgres 0750 1000 1000 -"
      "d ${cfg.dataDir}/secrets 0750 1000 1000 -"
    ];

    # Docker containers configuration
    virtualisation.oci-containers = {
      backend = "docker";
      containers = {
        "twenty-postgres" = {
          image = "postgres:15.3-alpine";
          environment = {
            POSTGRES_USER = "twenty";
            POSTGRES_PASSWORD = cfg.postgresql.password;
            POSTGRES_DB = "twenty";
            PGDATA = "/var/lib/postgresql/data";
          };
          volumes = [
            "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
          ];
          extraOptions = [
            "--network=twenty-network"
          ];
        };

        "twenty-server" = {
          image = "twentycrm/twenty-server:latest";
          dependsOn = [ "twenty-postgres" ];
          environment = {
            PORT = "3000";
            PG_DATABASE_URL = "postgresql://twenty:${cfg.postgresql.password}@twenty-postgres:5432/twenty";
            FRONT_BASE_URL = "http://localhost:${toString cfg.port}";
          };
          extraOptions = [
            "--network=twenty-network"
          ];
        };

        "twenty-front" = {
          image = "twentycrm/twenty-front:latest";
          dependsOn = [ "twenty-server" ];
          ports = [
            "${toString cfg.port}:3000"
          ];
          environment = {
            FRONT_URL = "http://localhost:${toString cfg.port}";
            API_URL = "http://twenty-server:3000";
          };
          extraOptions = [
            "--network=twenty-network"
          ];
        };
      };
    };

    # Create Docker network and initialize secrets
    systemd.services.twenty-init = {
      description = "Initialize Twenty environment";
      path = [ pkgs.docker ];
      script = ''
        # Create network if it doesn't exist
        if ! docker network inspect twenty-network >/dev/null 2>&1; then
          docker network create twenty-network
        fi
        
        ${generateSecret}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker.service" ];
      after = [ "docker.service" ];
    };

    # Health check service
    systemd.services.twenty-healthcheck = {
      description = "Twenty health check";
      script = ''
        # Check if services are running
        docker ps | grep -q twenty-front
        docker ps | grep -q twenty-server
        docker ps | grep -q twenty-postgres
        
        # Check port availability
        ${pkgs.netcat}/bin/nc -z localhost ${toString cfg.port}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wantedBy = [ "multi-user.target" ];
      after = [ "twenty-init.service" ];
    };
  };
}