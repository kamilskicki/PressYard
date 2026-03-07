# PressYard Manual

## 1. Design Goals

This workspace is optimized for:

- cloning the same template into many parallel WordPress environments
- keeping startup and steady-state resource use low enough for several active stacks
- supporting both disposable QA/test runs and longer-lived client development
- avoiding Docker Desktop proxy/router failure modes that depend on container access to the Docker socket

The important architectural choices are:

- WordPress core lives in a named volume, not in a host bind mount
- MariaDB lives in a named volume with lower-memory local-dev tuning
- only `wp-content/plugins`, `wp-content/mu-plugins`, `wp-content/themes`, and `wp-content/uploads` are bind-mounted
- the shared proxy is file-driven and routes to `host.docker.internal:<published-port>` instead of discovering containers through the Docker socket

## 2. Files and Services

Main services:

- `db`
- `wordpress`
- `wp-init`
- `wp-cli` via profile `ops`
- `adminer` via profile `tools`
- shared Traefik proxy from `docker-compose.proxy.yml`

Important paths:

- `wp-content/` for live code and media
- `packages/` for plugin/theme ZIPs
- `backups/` for exported SQL dumps
- machine-level proxy route files in `PROXY_CONFIG_DIR` from `.env`

Host support:

- Windows PowerShell: primary target
- macOS + Linux with PowerShell 7: supported path
- one PowerShell codepath is preferable to maintaining parallel shell implementations

## 3. Bootstrap and Identity

Run this once per copied folder:

```powershell
.\scripts\bootstrap-env.ps1
```

It generates or updates:

- `COMPOSE_PROJECT_NAME`
- `WP_HOSTNAME`
- `WORDPRESS_PUBLISHED_PORT`
- `ADMINER_PUBLISHED_PORT`
- `WP_URL`
- `PROXY_CONFIG_DIR`
- `HOST_RESOLUTION_MODE`

Default behavior:

- folder `project1` becomes `COMPOSE_PROJECT_NAME=project1`
- hostname becomes `project1.localhost`
- containers, volumes, and networks use the `project1` prefix

Collision behavior:

- if `project1` is already owned by another live stack, the scripts fall back to `project1-<hash>`

That fallback is for the internal Docker namespace. Old volumes by themselves no longer force a hash suffix. The browser hostname remains `project1.localhost` unless another active route already owns it.

## 4. Start Modes

### Default one-command boot

```powershell
.\up.ps1
```

Default behavior:

- detached mode
- shared proxy enabled
- clean `.localhost` routing required
- direct WordPress port still available

### Direct-only

```powershell
.\up.ps1 -WithProxy:$false
```

Use:

- `http://localhost:<WORDPRESS_PUBLISHED_PORT>`

### Direct + shared hostname router

```powershell
.\up.ps1
```

Use:

- `WP_URL` from `.env`
- `http://localhost:<WORDPRESS_PUBLISHED_PORT>` as fallback
- `.\up.ps1` requires an elevated terminal so it can update the hosts file

### Direct + router + Adminer

```powershell
.\up.ps1 -WithTools
```

Use:

- WordPress direct: `http://localhost:<WORDPRESS_PUBLISHED_PORT>`
- WordPress proxy: `WP_URL`
- Adminer direct: `http://127.0.0.1:<ADMINER_PUBLISHED_PORT>`
- Adminer proxy: `http://db-<WP_HOSTNAME>:<PROXY_HTTP_PORT>`

## 5. Shared Proxy Model

The proxy is intentionally decoupled from Docker discovery.

Why:

- Docker Desktop socket access from containers is not reliable enough across machines
- every project already has a unique published host port
- a static route file per project is enough to restore the hostname UX
- one global proxy is cheaper than one proxy per project

The shared proxy Compose project name defaults to `pressyard-proxy`.

Route flow:

1. `proxy-sync.ps1` writes `<COMPOSE_PROJECT_NAME>.yml` into `PROXY_CONFIG_DIR`
2. `hosts-sync.ps1` maps `WP_HOSTNAME` and optional `db-<WP_HOSTNAME>` to `127.0.0.1`
3. Traefik watches that directory
4. requests for `WP_HOSTNAME` route to `host.docker.internal:<WORDPRESS_PUBLISHED_PORT>`
5. requests for `db-<WP_HOSTNAME>` route to `host.docker.internal:<ADMINER_PUBLISHED_PORT>`

Useful commands:

```powershell
.\scripts\proxy-up.ps1
.\scripts\proxy-down.ps1
.\scripts\proxy-sync.ps1 -WithTools
.\scripts\hosts-sync.ps1 -WithTools
.\open.ps1
```

## 6. WordPress Initialization

`wp-init` handles:

- first-time `wp core install`
- deletion of default plugins
- ZIP package install
- fallback activation of `local-dev-theme`
- deletion of inactive default `twenty*` themes

ZIP scan order:

1. `packages/*.zip`

Package state is cached in a named volume so unchanged ZIP sets are skipped on later boots.

## 7. WP-CLI

Use the wrapper:

```powershell
.\wp.ps1 plugin list
.\wp.ps1 theme list
.\wp.ps1 option get siteurl
.\wp.ps1 search-replace old.example new.example --skip-columns=guid
```

`wp-cli` is an on-demand service and does not come up with the default stack.

## 8. DB Export and Import

Export:

```powershell
.\export-db.ps1
.\export-db.ps1 .\backups\client-a-before-migration.sql
```

Import:

```powershell
.\import-db.ps1 .\backups\client-a-before-migration.sql
```

Use this for:

- staging snapshots
- migration checkpoints
- restoring a persistent environment after destructive testing

## 9. Stop and Destroy

Stop but keep data:

```powershell
.\down.ps1
```

Stop and wipe project data volumes:

```powershell
.\down.ps1 -Volumes
```

`down.ps1` also removes the project’s shared-proxy route file.
It also removes the project’s managed hosts-file entries.

To stop the shared proxy too:

```powershell
.\down.ps1 -Proxy
```

## 10. Recommended Throughput Practices

For highest practical throughput when running many stacks:

- keep the repo in WSL2 storage when possible
- avoid bind-mounting the entire WordPress root
- keep bulky one-off ZIPs in `packages/` instead of scattering them through project roots
- use `down.ps1` for persistent stacks and reserve `-Volumes` for true throwaways
- export DB snapshots before risky plugin/theme work
- only start `adminer` when needed
- keep personal ZIP bundles in `packages/` so the repo root stays publishable

## 11. Common Workflows

### New client environment

```powershell
Copy-Item D:\docker\pressyard D:\docker\clients\client-a -Recurse
cd D:\docker\clients\client-a
.\scripts\bootstrap-env.ps1
.\up.ps1 -WithTools
```

The default URLs become:

- `http://client-a.localhost`
- `http://db-client-a.localhost`

### One-off plugin/theme smoke test

```powershell
Copy-Item D:\docker\pressyard D:\docker\scratch\plugin-test -Recurse
cd D:\docker\scratch\plugin-test
.\scripts\bootstrap-env.ps1
.\up.ps1 -WithProxy:$false
# test
.\down.ps1 -Volumes
```

### Persistent client work with snapshot

```powershell
.\up.ps1
.\export-db.ps1 .\backups\before-redesign.sql
# work
.\down.ps1
```

## 12. Current Tradeoffs

- The proxy defaults to `80`/`8089` so the primary site URL can be `http://name.localhost` with no extra port.
- `WP_URL` is the proxy URL by design. If the proxy is not running, use the direct port.
- `.localhost` resolution depends on the script being able to update your hosts file. For the cleanest UX, run `.\up.ps1` in an elevated terminal. If you do not want that, use `.\up.ps1 -WithProxy:$false` and work on the direct port.
- Adminer remains optional and older than the WordPress container runtime; it is isolated behind its own profile and direct port.
- Renaming an already-used folder creates a new compose namespace and new volumes. That is correct for copied environments, but if you intend an in-place rename without changing persistence, keep `COMPOSE_PROJECT_NAME` fixed in `.env`.
- The repo is publish-clean only if personal ZIPs remain in ignored paths like `packages/`; do not recommit commercial bundles into the root.
