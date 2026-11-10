# Installing DEASys on Windows 64-bit

DEASys is one program with its screens built in. It runs on your own computer and you use it in your browser.

## Quick install (about 3 minutes)

1. Download **`bin/DEASys-0.1.0-win64.zip`** and check it against **`bin/SHA256SUMS.txt`**
   (PowerShell: `Get-FileHash .\DEASys-0.1.0-win64.zip -Algorithm SHA256`).
2. Unzip it, open **PowerShell as Administrator** in the unzipped folder and run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\install.ps1
   ```

3. Choose the database: **bundled PostgreSQL** (recommended: the installer downloads PostgreSQL 16 from the official
   EnterpriseDB link once, about 330 MB, checks its SHA-256 and sets it up for you) or an **existing PostgreSQL**
   server you already run (version 13 or newer).
4. When it finishes, your browser opens `http://localhost:8080/`. The first screen creates your organisation, your first
   branch and the administrator account. Then sign in.

Needs: Windows 10 or 11 / Server 2016 or newer, 64-bit, about 1 GB free disk, administrator rights for the install, and
internet access once for the bundled database download.

## What the installer does

- Copies the program to `C:\Program Files\DEASys` and keeps your data in `C:\ProgramData\DEASys` (configuration, logs, backups).
- Sets up the database (bundled PostgreSQL on its own port, loopback only, as the Windows service **DEASysDB**) and applies the schema.
- Installs and starts the Windows service **DEASys** (starts automatically).
- Adds Start Menu and desktop shortcuts that open the app.
- Listens on this computer only. To allow other computers on your network, re-run with `-AllowNetwork` (and put HTTPS in front for anything beyond a trusted LAN).

## Upgrade

Download the newer zip and run `install.ps1` again. It backs up the database first, replaces the program, applies new
schema changes and starts the service. If the new version fails to start, it puts the old files and database back.

## Uninstall

`.\uninstall.ps1` removes the services and the program and **keeps your data and backups**. To delete the data too:
`.\uninstall.ps1 -RemoveData` (you must type the confirmation phrase).

## Other files in `bin/`

| File | What it is |
|---|---|
| `deasys-server-windows-amd64.exe` | The program on its own (for people who set up the database themselves). Run `deasys-server.exe config init`, then `migrate`, `init-admin`, `run`. |
| `deasys-server-linux-amd64` | The same program for Linux. |
| `SHA256SUMS.txt` | Checksums of all files above. |

## Important

- These builds are **not code-signed** yet. Windows SmartScreen may say "Windows protected your PC": choose **More info**, then **Run anyway**.
- The licence in `windows/LICENSE.txt` is a **draft pending legal review**.
- The full guide with screenshots is in [README.md](README.md). The installer scripts are in the [`windows/`](windows) folder, so you can read exactly what they do before running them.
