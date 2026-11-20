# Deploying MicrosoftMCP

A generic example for one Linux host with systemd and nginx. Host names are placeholders; adjust paths and names to your setup. Install and configure the auth server first, see the [MCPAuth4D deployment guide](https://github.com/GDKsoftware/MCPAuth4D/blob/main/docs/deployment.md).

## Files

| File | Install as |
|------|-----------|
| `microsoftmcp.service` | `/etc/systemd/system/microsoftmcp.service` |
| `microsoftmcp.env.example` | `/etc/microsoftmcp/microsoftmcp.env` |
| `nginx/microsoftmcp.conf.example` | a site in `/etc/nginx/sites-available/`, linked from `sites-enabled/` |

## Layout

```
/opt/microsoftmcp/
  MicrosoftMcp               Linux64 Release build of Source/MicrosoftMcp.dpr
  migrations/postgres/       copy of the migrations/postgres folder of the repository
/etc/microsoftmcp/
  microsoftmcp.env           settings and secrets (mode 0640, owner root:microsoftmcp)
```

## Steps

```
sudo apt-get install -y libssl3 libcurl4 libpq5
sudo useradd --system --home /opt/microsoftmcp --shell /usr/sbin/nologin microsoftmcp
```

1. Create a PostgreSQL database and a role that owns it. The program applies its migrations at every start.
2. Generate a service secret, put its hash in the registry of the auth server (`MCPAuthServer --hash-secret`) and the secret itself in `microsoftmcp.env`. The README of the repository has the registry entry.
3. Fill in `microsoftmcp.env`, then:

```
sudo systemctl daemon-reload
sudo systemctl enable --now microsoftmcp
journalctl -u microsoftmcp -f
```

4. Install the nginx site, check it and reload: `sudo nginx -t && sudo systemctl reload nginx`.

## Notes

- The program listens on `127.0.0.1` only. nginx publishes just `/mcp` and the protected-resource metadata; nothing else of the server is reachable from outside.
- The unit runs as its own user, with `NoNewPrivileges` and `ProtectSystem=strict`. The program writes nothing to disk, so it needs no writable paths. The log goes to standard output and so to the journal.
- SIGTERM stops the endpoint and the maintenance thread before the process exits.
- The `location ^~ /.well-known/oauth-protected-resource` prefix covers the metadata path `/.well-known/oauth-protected-resource/mcp` that clients derive from the resource URI. When the resource URI has another path, the metadata path follows it and the prefix still matches.
- Pending confirmations live in memory. A restart cancels them; the assistant asks again.

## Checks

```
curl -s -D - -o /dev/null -X POST https://m365.example.com/mcp                                  # 401, WWW-Authenticate with resource_metadata
curl -s https://m365.example.com/.well-known/oauth-protected-resource/mcp                      # authorization_servers lists the issuer
```
