# Windows packaging: what was tested, what was not, and the owner's checklist

Status of stage 2 (Windows packaging), written with the code. Read it before shipping any build.

## 1. Tested on the build machine (Windows 10 Pro 10.0.19045, x64, PowerShell 5.1, no administrator rights)

| Area | How | Result |
|---|---|---|
| Embedded web interface in the server executable | Built `deasys-server.exe` with the UI embedded (UI built from `webtally-ui`, copied into `server-go\internal\webui\dist` for the build only, then the tracked placeholder restored) | `GET /` serves the UI (text/html) |
| Portable bundled install (`install.ps1 -Portable -DbMode bundled`) | PostgreSQL **13.6** binaries from `C:\PostgreSQL\13\bin` as the stand-in, cluster in a temp folder, port **5439**, app port **8089** | initdb, loopback-only settings, application role and database, configuration file, migrations 000 to 003 applied, server started as a process, health check passed |
| First run, sign-in | `POST /api/v1/setup/first-run` (201), `POST /api/v1/auth/login` (token) | passed |
| Fresh-install smoke test (`scripts/smoke-fresh-install.ps1`) | every parameterless GET route of the OpenAPI document, with context parameters | 108 routes called: **81 x 2xx, 27 x 4xx** (routes that need a specific parameter, not failed), **0 x 5xx** |
| Backup | `deasys-server backup` (done by the installer before each upgrade) | custom-format dump written, never overwritten |
| Restore | `deasys-server restore <dump>` into an empty throwaway database | restored: user rows and schema migration rows present |
| Upgrade 1.0.0 to 1.0.1 | `install.ps1` from the newer package over the same folders | backup, previous files kept, files replaced, migrate (no-op), start, health check passed, version reported 1.0.1 |
| Upgrade with rollback | package 1.0.2 whose executable is deliberately truncated (not a valid Win32 application) | backup, migrate failed, **previous files restored, database restored from the backup (`restore --force`), previous version started, health check passed, exit 1**; sign-in still worked afterwards |
| Re-run over existing data (repair) | `install.ps1` again over the kept data folder | database reused, no re-initdb, migrations no-op, passed |
| Existing-server mode (`-DbMode existing -Unattended`, connection in environment variables) | a second portable instance against a throwaway database on the same cluster | configuration written, migrations applied, server healthy |
| Refusal without administrator rights | `install.ps1` without `-Portable` | refused with a clear message, exit 1, nothing written |
| Uninstall, keep data (`uninstall.ps1 -Portable`) | after the tests | server process stopped, database stopped (pg_ctl), program files removed, data, backups and log kept |
| Uninstall, wrong confirmation | `-RemoveData -ConfirmRemoveData delete` | data kept, message printed |
| Uninstall, confirmed removal | `-RemoveData -ConfirmRemoveData "DELETE DEASYS DATA"` | data folder removed |
| Clean teardown | process and port sweep afterwards | no test process or listener left |
| Zip build (`build-zip.ps1`) | 1.0.0, 1.0.1 and the broken 1.0.2 packages | zip and `SHA256SUMS.txt` written; zip is about 7.4 MB without PostgreSQL |
| Installer compiler detection (`build-installer.ps1`) | Inno Setup is not installed | prints where to get it, exit 3 |
| Signing hook (`sign.ps1`) | no `DEASYS_SIGN_THUMBPRINT` | says the files are not signed, exit 0 |
| PostgreSQL fetch guard (`fetch-postgres.ps1`) | placeholder hash in `postgres-pin.psd1` | refuses to run, exit 1 |
| Parsing | every `.ps1` in `packaging\windows` and `server-go\scripts` | no syntax errors (PowerShell parser) |
| Baseline drift check (`check-baseline-drift.ps1` and `.sh`) | throwaway database built from baseline and migrations, compared with the reference database | no product-relevant drift (both scripts) |

The bugs found and fixed during these runs were: `pg_ctl start` blocked when called from PowerShell with captured output
(postgres inherits the handles), so the database is now started with `postgres.exe` and polled with `pg_isready`;
an interrupted install was mistaken for an upgrade (an upgrade now needs an executable and a configuration file); the
uninstaller could not find `pg_ctl` in test mode (it now reads `pg_bin` from the configuration); the test secret file's ACL
locked out the test user (test mode now grants the current user); a failure after the program files changed did not
roll back (it now does).

## 2. Not tested here (must be tested on a real Windows machine before release)

- **Windows services**: `DEASysDB` (PostgreSQL via `pg_ctl register`, dedicated local account, automatic start),
  `DEASys` (`deasys-server service install|start|stop|uninstall`), automatic start at boot, recovery actions.
  None of this was run: the build machine is not elevated.
- **Service account ACLs** on `pgdata`, `deasys.conf` (LocalService read) and the superuser secret file.
- **Firewall rule** (`New-NetFirewallRule`, private and domain profiles) when `-AllowNetwork` is chosen.
- **Shortcuts** (`DEASys.url` in the Start Menu and on the desktop).
- **The Inno Setup installer**: `deasys.iss` has **not been compiled**. Inno Setup is not installed here. Expect to fix
  small Pascal or directive issues on the first compile. Check: the custom database and network pages, the
  `PrepareToInstall` upgrade hook (`install.ps1 -Phase Prepare`), the `CurStepChanged` install step, the uninstall hook.
- **Bundled PostgreSQL 16 binaries**: the pin (`postgres-pin.psd1`) names 16.4-1 and a placeholder hash. The URL and the
  SHA-256 must be checked against the official download before release. Only PostgreSQL 13.6 binaries were run.
- **`build-all.ps1` end to end**: it calls `build-ui.ps1` and `build-release.ps1` (which run `npm` and `go test`). The
  pieces it calls were run separately (UI build in a copy, `go build`, `build-zip.ps1`), but not the orchestrator itself.
- **Signing with a real certificate** (`sign.ps1` with a thumbprint, `signtool`, timestamping).
- **Linux**: the Linux binary is built by `build-release`, and the systemd unit is in `deploy\linux` (not part of this work).
- **Go test suite**: see section 4.

## 3. Manual checklist for the owner (Windows 10/11 x64, elevated PowerShell where marked)

Run each step on a clean machine (VM snapshot recommended). Keep the `install.log` for each run.

1. **Build** (on the build machine): `packaging\windows\fetch-postgres.ps1` (after the pin is verified), then
   `packaging\windows\build-all.ps1 -Version 1.0.0`. Check `dist-release\SHA256SUMS.txt` against the files.
2. **Zip, fresh install** (admin): extract, run `install.ps1`. Answer "B" (bundled), the network question "N".
   Expect: services `DEASys` and `DEASysDB` running (`Get-Service DEASys,DEASysDB`), `http://localhost:8080/health`
   returns 200, the browser opens the first-run page, the Start Menu shortcut works.
3. **First run and sign-in**: create the company and the administrator, sign in, open a list screen and a report.
4. **Services survive a reboot**: restart Windows; both services start; the site answers.
5. **Permissions**: as a standard (non-admin) user, `deasys.conf` and `pgsuper.secret` cannot be read; the service still
   starts (open `services.msc`, check the log on tab of `DEASys` is LocalService).
6. **Network option**: re-run `install.ps1 -AllowNetwork`; from another computer on the private network, the site opens;
   from a public network profile it does not. `Get-NetFirewallRule "DEASys web interface (TCP)"` shows the rule.
7. **Backup and restore**: run the backup command from README-FIRST.txt; restore it into an empty database
   (`deasys-server.exe restore <file>` with a new `database_url`), then start the server against it.
8. **Upgrade**: install the next version with `install.ps1` (or the installer). Check a new backup in
   `%ProgramData%\DEASys\backups`, the version (`deasys-server.exe version`), and the health check.
9. **Upgrade rollback**: use a deliberately broken package (for example a truncated `deasys-server.exe`). Expect: the
   old version back, the database restored, the site working, exit code 1, and the reason in `install.log`.
10. **Existing server**: a second machine or a second installation with `install.ps1 -DbMode existing`; the password is
    typed hidden; `install.log` must not contain it.
11. **Installer (Inno)**: compile `deasys.iss` with `build-installer.ps1` (Inno Setup 6). Repeat steps 2, 8 and 9 through
    the wizard. Check the uninstall keeps `%ProgramData%\DEASys`.
12. **Uninstall**: Settings > Apps > DEASys > Uninstall. Services gone, program folder gone, `%ProgramData%\DEASys`
    kept. Then `uninstall.ps1 -RemoveData` with the typed phrase: data gone.
13. **Signing** (when a certificate exists): set `DEASYS_SIGN_THUMBPRINT`, rebuild, check
    `Get-AuthenticodeSignature` is Valid on the exe and the installer. Test SmartScreen on a fresh download.
14. **Unsigned builds**: expect a SmartScreen "Windows protected your PC" warning. Tell users: "More info", then
    "Run anyway", after checking the SHA-256 against `SHA256SUMS.txt`. Signing with a code-signing certificate
    (ideally EV, or OV with reputation) removes or reduces the warning; it does not remove it on day one for an OV
    certificate.

## 4. Other gaps to decide before release

- **`go test ./...`**: 58 packages pass. Eight fail on a fresh-schema database because their integration tests need rows
  of the reference installation (branch 1000, centre 1000, company 100, ledger 727, financial year 2026). The baseline
  deliberately carries no organisation data, so these cannot pass on a fresh database. `TestGSTR1GoldenBody` (no database)
  fails on this branch independently of the packaging work: no Go source changed here. Run the suite against a
  reference-fixture database, and fix or regenerate the golden file, before the release tag.
- **Smoke test coverage**: 27 GET routes answer 4xx without their specific parameters. Extend the smoke test with the
  parameters the UI sends (or a per-route table) when the UI menus are final.
- **Bundled PostgreSQL size**: not measured. The PostgreSQL 16 binaries are on the order of 250 to 350 MB unpacked;
  the release zip with them will be correspondingly large.
- **PostgreSQL superuser password** is kept in `%ProgramData%\DEASys\pgsuper.secret` (service mode: SYSTEM and
  administrators only). Decide whether to keep it there or to require the owner to note it.
- **Legal**: `LICENSE.txt` is a draft for legal review (governing law, liability cap and third-party list are marked).
