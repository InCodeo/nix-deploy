# modules/docker/twenty.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.twenty;
  
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
    # Create required directories first
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 1000 1000 -"
      "d ${cfg.dataDir}/postgres 0750 1000 1000 -"
      "d ${cfg.dataDir}/secrets 0750 1000 1000 -"
    ];

    # Initialize environment before starting containers
    systemd.services.twenty-init = {
      description = "Initialize Twenty environment";
      path = [ pkgs.docker ];
      script = ''
        # Wait for Docker to be fully started
        for i in {1..30}; do
          if docker info >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # Create network if it doesn't exist
        if ! docker network inspect twenty-network >/dev/null 2>&1; then
          docker network create twenty-network
        fi
        
        ${generateSecret}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "2min";
      };
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker.service" ];
      after = [ "docker.service" "network.target" ];
    };

    # Docker containers with improved dependency management
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
            "--health-cmd=pg_isready"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
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
            "--health-cmd=curl -f http://localhost:3000/health || exit 1"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
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

    # Health check service with timeout
    systemd.services.twenty-healthcheck = {
      description = "Twenty health check";
      script = ''
        # Wait for containers to be ready
        for i in {1..60}; do
          if docker ps | grep -q twenty-front && \
             docker ps | grep -q twenty-server && \
             docker ps | grep -q twenty-postgres; then
            break
          fi
          sleep 2
        done

        # Check port availability
        ${pkgs.netcat}/bin/nc -z localhost ${toString cfg.port}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      wantedBy = [ "multi-user.target" ];
      after = [ "twenty-init.service" "network.target" ];
    };
  };
}