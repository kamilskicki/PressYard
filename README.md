# PressYard

Local WordPress environments that behave like products, not chores.

Copy the folder. Rename it. Run one command. Get:

- a readable local hostname based on the folder name
- isolated containers, volumes, and ports
- WordPress installed automatically
- latest WordPress core on the configured PHP line
- optional package ZIP installs from `packages/`
- a shared proxy for clean per-project URLs across many projects

## Why This Exists

Most WordPress Docker setups are good at starting one site once.

They are bad at:

- spinning up many parallel client environments
- surviving folder copies and renames without manual cleanup
- staying understandable for normal developers
- keeping the repo publishable instead of turning it into a pile of local-only hacks

PressYard is designed for the copy-heavy reality of WordPress work:

- new client sandbox
- plugin smoke test
- staging clone
- persistent theme/plugin development

## Fast Start

Open PowerShell as Administrator, then from the repo root run:

```powershell
.\doctor.ps1
.\up.ps1
```

Or use one of the optional dev profiles:

```powershell
.\up.ps1 -WithTools
.\up.ps1 -WithMail
.\up.ps1 -WithXdebug
.\up.ps1 -WithTools -WithMail -WithXdebug
```

That will:

1. derive the stack name from the folder name
2. generate `.env`
3. choose free direct ports
4. map `<project>.localhost` into your hosts file
5. start WordPress
6. start the shared proxy
7. print the full installation path and live URLs

If you skip the elevated terminal, use `.\up.ps1 -WithProxy:$false` and work on the printed direct port instead.

## Mental Model

If your folder is named `project1`, PressYard will try to use:

- `COMPOSE_PROJECT_NAME=project1`
- containers like `project1-wordpress-1`
- volumes like `project1_wp_data`
- `http://project1.localhost`
- `http://db-project1.localhost` with Adminer

If `project1` is already owned by another live stack on your machine, PressYard falls back to:

- `project1-<hash>`

That fallback applies to the internal Docker project namespace only when a live stack already owns the clean name. The public browser hostname stays tied to the folder name whenever that hostname is available.

## Core Commands

```powershell
.\up.ps1
.\up.ps1 -WithTools
.\up.ps1 -WithMail
.\up.ps1 -WithXdebug
.\down.ps1
.\down.ps1 -Volumes
.\wp.ps1 plugin list
.\logs.ps1 wordpress -Follow
.\open.ps1
.\open.ps1 -Adminer
.\open.ps1 -Mailpit
.\reset.ps1 -WithTools
.\doctor.ps1
.\export-db.ps1
.\import-db.ps1 .\backups\snapshot.sql
```

## What Gets Mounted

For performance, PressYard does not bind-mount the entire WordPress root.

Bind-mounted:

- `wp-content/plugins`
- `wp-content/mu-plugins`
- `wp-content/themes`
- `wp-content/uploads`

Docker volumes:

- WordPress core/runtime
- MariaDB data
- init/package state

PressYard also keeps WordPress runtime update directories writable so core, plugin, and theme updates from wp-admin do not fail on container permissions.

That balance is the main reason this setup stays usable when several projects are running.

## Package ZIPs

Drop plugin or theme ZIPs into:

- `packages/`

On first boot, PressYard will attempt:

1. plugin install
2. theme install

If the ZIP set has not changed, later boots skip reinstall.

`packages/` is ignored by Git on purpose so personal/commercial plugin bundles stay local.

## Dev Profiles

Optional profiles are intentionally off by default so the fastest path stays fast.

- `-WithTools` starts Adminer
- `-WithMail` starts Mailpit and routes `wp_mail()` into the local inbox automatically
- `-WithXdebug` swaps the WordPress web container to the Xdebug-enabled image

You can also persist them in `.env`:

- `ENABLE_MAILPIT=true`
- `ENABLE_XDEBUG=true`

## Shared Proxy

By default, `.\up.ps1` starts a shared Traefik instance on:

- `127.0.0.1:80`
- dashboard on `127.0.0.1:8089`

Why port `80` by default:

- it gives the cleanest possible local URL
- subdomain routing keeps projects unique without extra ports

If you do not want the proxy:

```powershell
.\up.ps1 -WithProxy:$false
```

You still get the direct published WordPress port.

The proxy is global across all project copies on the machine.
Its shared Compose project name defaults to `pressyard-proxy`.

When Mailpit is enabled, it also gets a clean proxy URL:

- `http://mail-<project>.localhost`

## Hostname Resolution

Subdomains of `localhost` are not resolved consistently across dev machines, especially on Windows.

PressYard handles that by managing explicit hosts-file entries for:

- `<project>.localhost`
- `db-<project>.localhost` when Adminer is enabled

If PowerShell is not running with permission to update the hosts file, `.\up.ps1` will stop and tell the user to rerun it in an elevated terminal.

If you do not want to run an elevated terminal, use:

```powershell
.\up.ps1 -WithProxy:$false
```

That skips the proxy and still gives a working direct URL on `http://localhost:<port>`.

## Supported Hosts

Primary target:

- Windows + PowerShell + Docker Desktop

Also supported in principle:

- macOS + PowerShell 7 + Docker Desktop
- Linux + PowerShell 7 + Docker Engine + Compose plugin

The repo intentionally uses PowerShell as the automation layer across platforms instead of maintaining parallel shell implementations.

## Mailpit And Xdebug

Mailpit:

- direct URL: `http://127.0.0.1:<MAILPIT_PUBLISHED_PORT>`
- proxy URL: `http://mail-<project>.localhost`
- WordPress mail is routed there automatically through a must-use plugin

Xdebug:

- enabled with `.\up.ps1 -WithXdebug` or `ENABLE_XDEBUG=true`
- uses `host.docker.internal` by default
- defaults:
  - mode: `debug,develop`
  - port: `9003`
  - IDE key: `VSCODE`

## Repo Hygiene

This repo is set up to be publishable:

- `MIT` licensed
- personal ZIP bundles ignored
- root ZIPs ignored
- line endings normalized through `.gitattributes`
- smoke workflow included in `.github/workflows/smoke.yml`

## Files That Matter

- [docker-compose.yml](./docker-compose.yml)
- [docker-compose.proxy.yml](./docker-compose.proxy.yml)
- [up.ps1](./up.ps1)
- [doctor.ps1](./doctor.ps1)
- [scripts/bootstrap-env.ps1](./scripts/bootstrap-env.ps1)
- [scripts/init-wordpress.sh](./scripts/init-wordpress.sh)
- [MANUAL.md](./MANUAL.md)

## Publish Checklist

Before pushing:

1. replace placeholder secrets in your local `.env` generated from [`.env.example`](./.env.example)
2. confirm `packages/` contains only local ignored ZIPs you actually want on your machine
3. decide your final GitHub repo name

## License

[MIT](./LICENSE)
