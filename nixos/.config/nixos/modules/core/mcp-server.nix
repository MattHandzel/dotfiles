{pkgs, ...}: {
  services.nginx = {
    virtualHosts."mcp.matthandzel.com" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Authorization $http_authorization;

        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Cookie $http_cookie;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:47771"; # Port your MCP server runs on
      };
    };
  };
  virtualisation.oci-containers.containers.personal-knowledge-mcp = {
    autoStart = true;

    # Use the image you built locally
    image = "personal-knowledge-mcp:latest";
    extraOptions = ["--pull=never"];

    # Ports (host:container)
    ports = ["47771:47771"];

    # Environment variables from your .env file
    environmentFiles = [
      /home/matth/Projects/obsidian-vault-text-mining/.env
    ];

    # Volumes: host → container
    volumes = [
      "/home/matth/Projects/obsidian-vault-text-mining/output:/app/output"
      "/home/matth/Projects/obsidian-vault-text-mining/context-rules.json:/app/context-rules.json:ro"
    ];

    # Command to run
    cmd = [
      "python"
      "-m"
      "self_extract.cli"
      "context"
      "serve"
      "--transport"
      "http"
      "--host"
      "0.0.0.0"
      "--port"
      "47771"
      "--auth-type"
      "google"
    ];
  };
}
