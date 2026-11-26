# Installing DEASys 0.2.0-beta.1 on Windows (64-bit)

This is a **beta**. Read the [known limitations in the README](README.md#known-limitations) before you install it.

DEASys runs on your own computer. You open it in a web browser at `http://localhost:8080/`.

The DEASys installer installs **DEASys only**. It downloads nothing and it does not install PostgreSQL. You install
PostgreSQL yourself first, as described below.

## 1. What you need before you start

| Item | Requirement |
|---|---|
| Windows | Windows 10 or Windows 11, 64-bit. Windows 10 is the only version tested so far. |
| Administrator rights | Needed to run the installer. Not needed for `-Portable` (test mode only). |
| PostgreSQL | **PostgreSQL 13 or later. PostgreSQL 16 or later is recommended.** PostgreSQL 13 no longer receives updates from PostgreSQL, so use 16 or later for a new installation. Tested with 13.6 and 16.4. Get it from [postgresql.org/download/windows](https://www.postgresql.org/download/windows/). Keep the password of the `postgres` administrator. The installer does not ask for it. |
| An empty database and a login | Created by you in step 2. The database must be empty. |
| A web browser | Any current browser, for the first-run screen. |
| Disk space | At least 1.5 GB free on the drive of the program folder and on the drive of the data folder. |

PostgreSQL must be installed and running before you start the installer.

## 2. Create the database and its login

Open **pgAdmin** or **psql** as the PostgreSQL administrator (`postgres`) and run these two statements. Choose your own
login name, database name and password. The names below are examples.

```sql
CREATE ROLE deasys_user LOGIN PASSWORD 'choose-a-strong-password';
CREATE DATABASE deasys_db OWNER deasys_user ENCODING 'UTF8';
```

- The login must **own** the database, or hold `CREATE` on the `public` schema of the database. Owning it is the simple way.
- The database must be **empty**. DEASys creates its own tables the first time it starts.
- DEASys needs no PostgreSQL extensions.

**The complete connection string for these examples** (the installer asks for the same parts one at a time):

```
postgres://deasys_user:choose-a-strong-password@localhost:5432/deasys_db?sslmode=prefer
```

- `deasys_user` is the login, `choose-a-strong-password` its password, `localhost:5432` the server and port, and `deasys_db` the database.
- A password with special characters must be URL-encoded: `@` becomes `%40`, `:` becomes `%3A`, `/` becomes `%2F`, `#` becomes `%23` and `?` becomes `%3F`.
- For a server on another computer, use its host name and `sslmode=require`.

## 3. Run the installer

1. Download the zip, **`DEASys-0.2.0-beta.1-win64.zip`**, and check it against **`SHA256SUMS.txt`**. In PowerShell:

   ```powershell
   Get-FileHash .\DEASys-0.2.0-beta.1-win64.zip -Algorithm SHA256
   ```

2. Unzip the **whole** folder. Do not run `deasys-server.exe` on its own; it is the program, not the installer.
3. Double-click **`Install DEASys.cmd`** and answer Windows' permission question. The window stays open so you can read every message.
   Or, in an administrator PowerShell window in the unzipped folder, run `.\install.ps1`.
4. The installer shows the **terms** first. Read them. If you are running the installer from PowerShell, type `ACCEPT` when asked. Anything else stops the install and changes nothing.
5. The installer asks for:
   - the **host** (default `localhost`),
   - the **port** (default `5432`),
   - the **database name**,
   - the **login name**,
   - the **password** (typed hidden; never shown or written to a log).

   It then tests the connection at once. If the test fails, it says why (server not reached, password refused, login missing,
   database missing, no permission to create tables, PostgreSQL older than 13) and asks again. Nothing is written to the
   computer until the connection works.
6. The installer runs its checks, prints what it will change and asks `Continue? (type Y to continue)`.
7. When it finishes, DEASys runs as the Windows service **DEASys**, and your browser opens `http://localhost:8080/`.

The installer copies the program to `C:\Program Files\DEASys`, writes the settings file `C:\ProgramData\DEASys\deasys.conf`
(it holds the database password and a signing key; only administrators and the service account can read it), registers
the service to start with Windows, and creates Start Menu and desktop shortcuts. It opens the firewall only if you choose
network access.

### Unattended install (for administrators)

The same answers can be given in advance. The password is never put on the command line.

```powershell
$env:DEASYS_DB_HOST = "localhost"
$env:DEASYS_DB_PORT = "5432"
$env:DEASYS_DB_NAME = "deasys_db"
$env:DEASYS_DB_USER = "deasys_user"
$env:DEASYS_DB_SSLMODE = "prefer"
$env:DEASYS_DB_PASSWORD = "choose-a-strong-password"
.\install.ps1 -Unattended -AcceptTerms
Remove-Item Env:DEASYS_DB_PASSWORD
```

`-AcceptTerms` is your acceptance of the terms. A password file can be named with `DEASYS_DB_PASSWORD_FILE` instead of
the password variable. The complete connection string can be given with `DEASYS_DATABASE_URL`.

Options: `-AllowNetwork` lets other computers on your private network open DEASys (do not expose it to the internet
without a TLS proxy in front of it). `-NoBrowser` and `-NoShortcuts` do what their names say.

## 4. First start in the browser

1. Open `http://localhost:8080/` (or the Start Menu shortcut). While no user exists, DEASys shows the first-run wizard.
2. Read and accept the terms.
3. Enter your company, your first branch, your name, a sign-in name and a password (at least 10 characters, with a letter and a digit). Choose the financial-year start month and the base currency.
4. Sign in. You are the administrator. You can create other users and give them roles (see [the guide, section 6.6](USER-GUIDE.md#66-roles-and-permissions)).

The first-run wizard works once. After the first administrator is created, nobody can use it again.

## 5. Upgrade from version 0.1.0

Run the new installer (or `install.ps1` from the new zip) over the existing installation. Your data is kept.

- The installer detects the existing installation and reuses its connection in `deasys.conf`. It asks for the connection again only if that connection fails.
- The database is **backed up first**, into `C:\ProgramData\DEASys\backups`.
- New database changes are applied when the new program starts. If the new version fails to start, the installer puts back the old program files and the old database.
- **Installs that used the bundled database** (0.1.0 installed its own PostgreSQL 16 as the service `DEASysDB`) keep that database, its data and its backups. The installer only starts the database when it is stopped. Upgrading these installs was tested.
- **Installs that used your own PostgreSQL server in 0.1.0** keep using that server. Make a backup first (section 8). This upgrade path has not been tested separately in this beta.
- The terms are asked again only when their version has changed.

## 6. Uninstall

Either use **Settings > Apps > DEASys > Uninstall**, or run `C:\Program Files\DEASys\uninstall.ps1` in an administrator PowerShell window.

The uninstaller first prints what it removes (the DEASys service, the firewall rule, the shortcuts and the program files) and what it keeps.

- **Without data removal (default):** the program is removed. Your database, backups, settings, logs and terms record are kept.
- **With data removal:** run `uninstall.ps1 -RemoveData` and type the confirmation phrase `DELETE DEASYS DATA` when asked. This deletes the DEASys data folder (`C:\ProgramData\DEASys`). Remove the database itself with pgAdmin or `DROP DATABASE` if you no longer need it.
- **PostgreSQL itself is not touched.** Uninstall it from Windows' Apps list if you no longer need it.

Make a backup before you remove data.

## 7. Using the program file on its own (advanced, testing)

You can run `deasys-server.exe` without the installer. You then create the settings file yourself:

```powershell
cd "C:\Program Files\DEASys"
.\deasys-server.exe config init --database-url "postgres://deasys_user:choose-a-strong-password@localhost:5432/deasys_db?sslmode=prefer"
.\deasys-server.exe run
```

If you start the program before a database is configured, it prints these same steps instead of closing silently.

The Linux program file, `deasys-server-linux-amd64`, is the same program. **The Linux build has not been tested in this beta.**

## 8. Backup

Run this in an administrator PowerShell window. A backup holds every password hash and the audit trail, so keep it private and copy it off this computer.

```powershell
& "C:\Program Files\DEASys\deasys-server.exe" backup "C:\ProgramData\DEASys\backups\manual-$(Get-Date -f yyyyMMdd-HHmm).dump"
```

## 9. Troubleshooting the installer

- **The installer says the server does not answer:** check the host, the port, and that PostgreSQL is running.
- **The password is refused, or the login does not exist:** check the login and password. Create the login as in step 2.
- **The database does not exist:** create it with the statement in step 2.
- **The login cannot create tables:** run `GRANT CREATE ON SCHEMA public TO deasys_user;` as the administrator, or make the login the owner of the database.
- **The PostgreSQL version is older than 13:** install PostgreSQL 16 or later.
- **The installer reports that port 8080 is in use:** stop the program that uses it, then run the installer again.
- **Log files:** `C:\ProgramData\DEASys\logs\install.log` (the installer; it contains no passwords) and `deasys.log` (the server). Send `install.log` with any report.

## Files the installer creates

| Path | What it is |
|---|---|
| `C:\Program Files\DEASys` | The program, `deasys-server.exe`, the web interface in `ui\`, the terms and the licence. |
| `C:\ProgramData\DEASys\deasys.conf` | The settings: the database connection and the signing key. Secret. |
| `C:\ProgramData\DEASys\backups` | Backups. Secret. |
| `C:\ProgramData\DEASys\logs` | `install.log` and `deasys.log`. |
| `C:\ProgramData\DEASys\terms-accepted.json` | The record of your acceptance of the terms. Holds no password. |

## Not yet tested

- The Windows Setup wizard (an Inno Setup installer) is not built or tested in this beta. Use `Install DEASys.cmd` or `install.ps1`.
- The Windows service and firewall steps were not tested on an administrator machine in this beta.
- The Linux program.
