# tests/twenty-test.nix

{ config, pkgs, ... }:

let
  postgresPassword = "twenty-test-password"; # Change this in production!
in
{
  imports = [
    ../modules/docker/twenty.nix
  ];

  networking.hostName = "twenty-test";

  services.twenty = {
    enable = true;
    port = 3333;
    postgresql.password = postgresPassword;
  };

  networking.firewall.allowedTCPPorts = [ 22 3333 ];

  programs.zsh.shellInit = ''
    twenty-test() {
      echo "Testing Twenty installation..."
      
      echo "1. Checking system requirements..."
      systemctl status resource-monitor
      
      echo "2. Checking Docker services..."
      docker ps | grep twenty
      
      echo "3. Checking port availability..."
      nc -z localhost 3333
      
      echo "4. Checking Twenty web interface..."
      curl -f http://localhost:3333 || echo "Warning: Twenty web interface not responding"
      
      echo "5. Checking database connection..."
      docker exec twenty-postgres pg_isready
      
      echo "6. Checking logs for errors..."
      journalctl -u twenty-init -n 50 --no-pager | grep -i error
      
      echo "Test complete."
    }

    twenty-logs() {
      docker logs twenty-front
      docker logs twenty-server
      docker logs twenty-postgres
    }

    twenty-reset() {
      echo "Stopping Twenty services..."
      docker stop twenty-front twenty-server twenty-postgres
      
      echo "Removing containers..."
      docker rm twenty-front twenty-server twenty-postgres
      
      echo "Removing volumes..."
      rm -rf /var/lib/twenty/*
      
      echo "Restarting services..."
      systemctl restart twenty-init
      
      echo "Reset complete. Run twenty-test to verify."
    }
  '';

  system.stateVersion = "24.05";
}