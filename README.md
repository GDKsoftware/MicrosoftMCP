# MicrosoftMCP

Microsoft 365 MCP server with multiple mailboxes per user, written in Delphi.

MicrosoftMCP gives an MCP client (an AI assistant, an IDE, ...) access to mail, calendar, contacts, people, SharePoint and OneDrive of Microsoft 365. A user can work with several mailboxes: their own mailboxes of different Microsoft accounts and shared mailboxes. Each mailbox gets a short name that the tools take as their `mailbox` parameter.

Sign-in and the linked Microsoft accounts come from a central auth server built with [MCPAuth4D](https://github.com/GDKsoftware/MCPAuth4D). MicrosoftMCP runs no OAuth flow of its own: it asks the auth server whether a token is valid, and fetches Microsoft access tokens for the accounts the user linked there.

## Mailboxes and short names

Every tool except `list_accounts`, `list_mailboxes` and `mailbox_add` takes a required `mailbox` parameter: the short name of a mailbox.

- A user links one or more Microsoft accounts on the account page of the auth server. `list_accounts` shows them.
- `mailbox_add` gives a mailbox a short name (`^[a-z0-9][a-z0-9-]{0,31}$`, unique per user). It is either the own mailbox of a linked account, or a shared mailbox (an address) that the account has FullAccess to. The own mailbox of an account is usually added once per account, for example `work` and `private`.
- `list_mailboxes` lists the short names, their display names and kind, and marks mailboxes whose account was unlinked or needs to be reconnected. `mailbox_rename` and `mailbox_remove` manage them. Removing a mailbox only removes the short name; nothing in Microsoft 365 changes.
- An unknown short name gives an error that lists the short names the user has. A short name of another user is unknown, never the mail of that user.
- The user comes from the validated token, never from a parameter.
- A shared mailbox needs FullAccess in Exchange and the user must have consented to the `.Shared` scopes. A Graph 403 produces a message that names both.
- Calendar, contacts, people, SharePoint and OneDrive tools use the account behind the mailbox. Several tenants work side by side, one per linked account.

## Tools

Tools marked with `*` need confirmation: the first call returns a summary and a `confirmation_token`; the same call with that token carries it out. A token works once, for one user, one tool and the same arguments, and expires after ten minutes. Read-only tools are annotated as such; tools that delete or reach other people are annotated destructive and open-world.

| Area | Tools |
|------|-------|
| Mailboxes | `list_accounts`, `list_mailboxes`, `mailbox_add`, `mailbox_rename`, `mailbox_remove`* |
| Mail | `mail_search`, `mail_list`, `mail_read`, `mail_list_folders`, `mail_list_attachments`, `mail_get_attachment`, `mail_get_signature`, `mail_create_draft`, `mail_update_draft`, `mail_create_reply_draft`, `mail_create_forward_draft`, `mail_delete_draft`, `mail_send_draft`*, `mail_send`*, `mail_forward`*, `mail_move`, `mail_mark_read`, `mail_delete`* |
| Calendar | `calendar_list`, `calendar_search`, `calendar_get`, `calendar_create`*, `calendar_update`*, `calendar_delete`*, `calendar_respond`*, `calendar_propose_time`*, `calendar_availability` |
| Contacts | `contacts_search`, `contacts_get`, `contacts_create`, `contacts_update`, `contacts_delete`* |
| People | `people_search`, `people_relevant` |
| SharePoint | `sharepoint_search_sites`, `sharepoint_list_files`, `sharepoint_search_files`, `sharepoint_read_file`, `sharepoint_list_pages`, `sharepoint_read_page` |
| OneDrive | `onedrive_list`, `onedrive_read`, `onedrive_upload`, `onedrive_create_folder`, `onedrive_move`, `onedrive_delete`* |

`calendar_create` and `calendar_update` only need confirmation when the event has attendees, because then invitations or updates reach other people.

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
| `MICROSOFTMCP_REQUEST_STATE_KEY` | optional | Signing secret for the `requestState` tokens of the MCP library. No tool of this server uses them, so you can leave it empty: the program then generates a random key per process. Set the same value on every instance only when several instances serve the same clients. |

A configuration error stops the program at startup with a message that names the variable, never its value.

With `postgres` the program applies the migrations at startup and records them in the table `microsoftmcp_schema_version`.

## Hooking up to an MCPAuth4D auth server

MicrosoftMCP needs an auth server built with MCPAuth4D, with the Microsoft provider configured (an Entra multi-tenant app registration whose redirect URI is `<issuer>/callback/microsoft`). Add this server to the resource registry of the auth server and restart it:

```json
{
  "resources": [
    {
      "resource": "https://m365.example.com/mcp",
      "name": "Microsoft 365",
      "service_id": "microsoftmcp",
      "service_secret_sha256": "<output of MCPAuthServer --hash-secret>",
      "providers": [
        {
          "provider": "microsoft",
          "scopes": [
            "email", "User.Read",
            "Mail.ReadWrite", "Mail.ReadWrite.Shared", "Mail.Send", "Mail.Send.Shared", "MailboxSettings.ReadWrite",
            "Calendars.ReadWrite", "Calendars.ReadWrite.Shared",
            "Contacts.ReadWrite", "Contacts.ReadWrite.Shared",
            "People.Read", "Files.ReadWrite.All", "Sites.ReadWrite.All"
          ]
        }
      ]
    }
  ]
}
```

- `resource` is the value of `MICROSOFTMCP_RESOURCE_URI`, `service_id` of `MICROSOFTMCP_SERVICE_ID`. The auth server adds `openid`, `profile` and `offline_access` itself.
- Generate the service secret, for example with `openssl rand -base64 32`, keep the secret in `MICROSOFTMCP_SERVICE_SECRET` and put only its hash in the registry.
- Grant the scopes in the Entra app registration as delegated Microsoft Graph permissions. Tenants that restrict user consent need an admin to grant consent.
- When this server gets a scope that existing accounts have not granted yet, those accounts show "Reconnect" on the account page until the user reconnects them. `list_mailboxes` marks the affected mailboxes.

## Running locally

Run an auth server with an `http://` resource URI and `MCPAUTH_ALLOW_HTTP_RESOURCES=1` (see the MCPAuth4D README), then start this server with the memory store:

```
MICROSOFTMCP_RESOURCE_URI=http://127.0.0.1:8090/mcp
MICROSOFTMCP_AUTH_ISSUER=http://127.0.0.1:8100
MICROSOFTMCP_SERVICE_ID=microsoftmcp
MICROSOFTMCP_SERVICE_SECRET=<the secret behind the registry hash>
MICROSOFTMCP_STORE=memory
```

The memory store loses all mailboxes on restart. Pending confirmations always live in memory. Point an MCP client at `http://127.0.0.1:8090/mcp`; it is sent to the auth server to sign in.

For production with systemd and nginx see [deploy/README.md](deploy/README.md).

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
- The tests use fake Graph transports and fake linked accounts: they need no Microsoft account. The FireDAC mailbox store tests need PostgreSQL and run only when `MICROSOFTMCP_TEST_PG` is set; `build/docker-compose.yml` starts a suitable database and the header of `build/test.ps1` has the details. Run the tests with and without it, on Win64 and on Linux64.
- On Win64 the build copies OpenSSL next to the executable from `OPENSSL_DIR` or a known install folder.

## Operating system dependencies

| Library | Windows | Linux |
|---------|---------|-------|
| OpenSSL 3 | `libcrypto-3-x64.dll`, `libssl-3-x64.dll` next to the executable (the build copies them from `OPENSSL_DIR` or a known install folder) | `libssl3` (`libcrypto.so.3`, `libssl.so.3`) |
| libpq (only with `MICROSOFTMCP_STORE=postgres`) | `libpq.dll` on the PATH | `libpq5` |
| libcurl | not needed | `libcurl4` |

On Debian or Ubuntu: `sudo apt-get install -y libssl3 libcurl4 libpq5`.

## Security notes

- Mail, calendar and file content, subjects, addresses and tokens are never written to the log.
- Anything that sends, deletes or reaches other people goes through the two-step confirmation described above. A token cannot be reused, used for other arguments, by another user or after it expired; a rejected attempt does not carry out the action.
- Graph errors are translated into messages that say what to do (reconnect the account, grant FullAccess, retry later).
- Users are authenticated only through the auth server: every request needs a token issued for this server's resource URI. Microsoft refresh tokens stay in the auth server; this server only handles short-lived access tokens.
- The endpoint listens on `127.0.0.1`. Publish it through a reverse proxy with TLS, and expose nothing but `/mcp` and the protected-resource metadata.
- Revoking a token at the auth server can take up to a minute to reach this server, because positive introspection results are cached for that long.

## License

MIT, see [LICENSE](LICENSE).
