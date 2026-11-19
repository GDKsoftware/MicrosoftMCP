# MicrosoftMCP

Microsoft 365 MCP server with multiple mailboxes per user, written in Delphi.

MicrosoftMCP gives an MCP client (an AI assistant, an IDE, ...) access to mail, calendar, contacts, people, SharePoint and OneDrive of Microsoft 365. A user can work with several mailboxes: their own mailboxes of different Microsoft accounts and shared mailboxes. Each mailbox gets a short name that the tools take as their `mailbox` parameter.

Sign-in and the linked Microsoft accounts come from a central auth server built with [MCPAuth4D](https://github.com/GDKsoftware/MCPAuth4D). MicrosoftMCP runs no OAuth flow of its own: it asks the auth server whether a token is valid, and fetches Microsoft access tokens for the accounts the user linked there.

## Requirements

- Delphi 12.2 or newer. Developed and tested with Delphi 13 on Win64 and Linux64.
- Git submodules in `lib/`: [Delphi-MCP-Server](https://github.com/GDKsoftware/Delphi-MCP-Server), [MCPAuth4D](https://github.com/GDKsoftware/MCPAuth4D), [Microsoft365-4D](https://github.com/GDKsoftware/Microsoft365-4D), [Spring4D](https://bitbucket.org/sglienke/spring4d) and [TaurusTLS](https://github.com/JPeterMugaas/TaurusTLS).
- A running MCPAuth4D auth server with this server in its resource registry.
- OpenSSL 3 (`libcrypto-3-x64.dll` and `libssl-3-x64.dll` next to the executable on Windows, `libcrypto.so.3` and `libssl.so.3` on Linux). With the `postgres` store also libpq (`libpq.dll` on the PATH on Windows, `libpq.so.5` on Linux).

Clone with submodules:

```
git clone --recurse-submodules https://github.com/GDKsoftware/MicrosoftMCP.git
```

or, in an existing clone, `git submodule update --init`. The nested submodules of `lib/mcpauth4d` are not needed.

## Configuration

| Variable | Required / default | Meaning |
|----------|--------------------|---------|
| `MICROSOFTMCP_RESOURCE_URI` | required | The public URI of the MCP endpoint, for example `https://mcp.example.com/microsoft/mcp`. Must match the `resource` of this server in the registry of the auth server. |
| `MICROSOFTMCP_AUTH_ISSUER` | required | The public base URL of the auth server (its `MCPAUTH_ISSUER`). A trailing `/` is removed. |
| `MICROSOFTMCP_AUTH_INTERNAL_URL` | `http://127.0.0.1:8101` | The internal listener of the auth server. |
| `MICROSOFTMCP_SERVICE_ID` | required | The `service_id` of this server in the registry. |
| `MICROSOFTMCP_SERVICE_SECRET` | required | The service secret whose hash is in the registry. |
| `MICROSOFTMCP_PORT` | `8090` | The port of the MCP endpoint. It listens on `127.0.0.1` only; a reverse proxy publishes it. |
| `MICROSOFTMCP_STORE` | `memory` | `memory` (everything is lost on restart; for development) or `postgres`. |
| `MICROSOFTMCP_DB` | required with `postgres` | FireDAC connection string, for example `DriverID=PG;Server=127.0.0.1;Port=5432;Database=microsoftmcp;User_Name=microsoftmcp;Password=...`. |
| `MICROSOFTMCP_MIGRATIONS` | `<exe folder>/migrations` | Folder that holds `postgres/NNNN_*.sql`. A build started from `bin/<platform>/<config>` finds the `migrations/` folder of the repository. |

A configuration error stops the program at startup with a message that names the variable, never its value.

With `postgres` the program applies the migrations at startup and records them in the table `microsoftmcp_schema_version`.

## Running

```
powershell -File build/build.ps1 -Project Source/MicrosoftMcp.dpr -Platform Linux64 -Config Release
```

The executable lands in `bin/<platform>/<config>`. It runs until Ctrl+C (Windows) or SIGINT/SIGTERM (Linux).

Quick checks against a running server:

```
curl -s -D - -o /dev/null -X POST http://127.0.0.1:8090/mcp                          # 401, WWW-Authenticate with resource_metadata
curl -s http://127.0.0.1:8090/.well-known/oauth-protected-resource/<path of the resource URI>   # authorization_servers = the issuer
```

## Building and testing

```
powershell -File build/test.ps1                     # Win64
powershell -File build/test.ps1 -Platform Linux64   # Linux64, runs inside WSL
```

- `build/env.ps1` holds the default toolchain paths. Override them in `build/env.local.ps1` (ignored by git); see `build/env.local.example.ps1`.
- The build fails on any hint or warning in the code of this repository.
- On Win64 the build copies OpenSSL next to the executable from `OPENSSL_DIR` or a known install folder.

## License

MIT, see [LICENSE](LICENSE).
