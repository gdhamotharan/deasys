DEASYS - READ THIS FIRST
=========================

DEASys is double-entry accounting software that runs on this computer and is used in a web browser.

WHAT DEASYS INSTALLS, AND WHAT YOU MUST HAVE FIRST
  The installer installs DEASys only. It downloads nothing and installs no other software. Before you start, have these:
  1. Windows 10 or 11, 64-bit.
  2. PostgreSQL 16 (PostgreSQL 13 or later works; 16 is recommended), already installed and running, from the official
     PostgreSQL download (https://www.postgresql.org/download/windows/). Install it with the standard installer and keep
     the password of its "postgres" superuser. The installer does not need that password.
  3. An empty database and a login (role) for DEASys. As the PostgreSQL superuser, run (in pgAdmin or psql):
         CREATE ROLE deasys_user LOGIN PASSWORD 'choose-a-password';
         CREATE DATABASE deasys_db OWNER deasys_user;
     Use the names you like; the installer asks for the same names. The role must be able to create tables in the
     database, which it can do when it owns the database.
  4. Administrator rights to run the installer (not needed with -Portable, the test mode).
  The Windows Visual C++ runtime and any other library the program needs are part of the DEASys executable or of Windows.
  If the installer reports a missing item, install it as described above and run the installer again.

PACKAGE CONTENTS
  deasys-server.exe (the DEASys program, with the web interface built in), ui\ (web interface files), install.ps1 and
  deasys-common.ps1 (installer), uninstall.ps1, Install DEASys.cmd (starts the installer), TERMS.txt, LICENSE.txt,
  README-FIRST.txt, VERSION.txt.

TERMS AND CONDITIONS
  - The DEASys Terms and Conditions are in TERMS.txt, in the folder of this package and in the program folder
    (C:\Program Files\DEASys\TERMS.txt). Read them. The DEASys Freeware Licence (LICENSE.txt) is part of them, and it is
    the licence of record.
  - You must accept the terms before DEASys is installed. The installer shows them first. An install started from
    PowerShell shows the terms in the console and asks you to type ACCEPT. Anything else stops the install and nothing
    is changed.
  - The acceptance is recorded in C:\ProgramData\DEASys\terms-accepted.json (the version of the terms, the time in UTC,
    your Windows user name, the computer name and how the acceptance was given). It holds no password.
  - A new version of the terms (a newer date on the "Version:" line of TERMS.txt) asks you to accept again, on the next
    install or upgrade and in the browser. An older or the same version does not ask again.
  - An unattended install (-Unattended) works only with -AcceptTerms: that switch is your acceptance.

HOW TO START THE INSTALL
  Unzip the WHOLE package, then double-click "Install DEASys.cmd" and answer Windows' permission question. It runs the
  installer and keeps the window open so every message can be read. (deasys-server.exe alone is NOT the installer: it is
  the program, and it needs the PostgreSQL database described above.)

THE CONNECTION TO POSTGRESQL
  The installer asks for: the host (default localhost), the port (default 5432), the database name, the login name and
  the password (typed hidden; it is never shown or logged). The SSL mode defaults to "prefer" on this computer and to
  "require" for any other host. The connection is tested at once. If it fails, the installer says why and asks again:
    - the server does not answer: check the host, the port and that PostgreSQL is running;
    - the password is refused, or the login does not exist: check the login and password; if the login does not exist,
      create it as shown in step 3 above;
    - the database does not exist: create it with the statement the installer shows;
    - the login cannot create tables: GRANT CREATE ON SCHEMA public TO <login>, or make the login the owner of the database;
    - the PostgreSQL version is older than 13: install PostgreSQL 16.
  Nothing is written to the computer until the connection works.
  An upgrade reuses the connection in deasys.conf and asks again only if that connection fails.
  Unattended install: set DEASYS_DB_HOST, DEASYS_DB_PORT, DEASYS_DB_NAME, DEASYS_DB_USER and DEASYS_DB_SSLMODE, and the
  password in DEASYS_DB_PASSWORD or in the file named by DEASYS_DB_PASSWORD_FILE (never on the command line).
  Advanced: a complete connection string can be given with DEASYS_DATABASE_URL (postgres://user:password@host:port/db).

BEFORE ANYTHING IS CHANGED
  The installer runs these checks first. If one fails, it stops, says why and changes nothing:
  - it runs with administrator rights (except in -Portable test mode);
  - the PostgreSQL connection works (see above);
  - the web port (8080) is free, unless it is held by the DEASys installation being upgraded;
  - no other Windows service called DEASys exists (unless this is an upgrade of DEASys);
  - the drive of the program folder and the drive of the data folder have at least 1.5 GB free.
  It then prints what it will change and asks "Continue? (type Y to continue)".

WHAT THE INSTALLER DOES
  - Copies the program to C:\Program Files\DEASys.
  - Creates the configuration file C:\ProgramData\DEASys\deasys.conf. It holds the database password and the sign-in
    key: keep it private. Only administrators and the service account can read it.
  - Registers the Windows service "DEASys" (the web server) to start with Windows. It creates no database service.
  - Creates Start Menu and desktop shortcuts that open http://localhost:8080.
  - Opens the firewall for DEASys only when you choose network access.

EXISTING INSTALLATIONS THAT USE THE BUNDLED DATABASE (earlier releases)
  An installation made by an earlier release may run its own database service "DEASysDB". The upgrade keeps that
  database, its data, its backups and its program files; the installer only starts the database when it is stopped.
  Uninstalling keeps the data unless you give -RemoveData and type the confirmation phrase.

FIRST RUN
  1. Open http://localhost:8080 (or the shortcut). DEASys shows the first-run form while no user exists.
  2. Accept the terms when asked.
  3. Enter your company, the first branch, your name, a sign-in name and a password (at least 10 characters, with a
     letter and a digit). Choose the financial-year start month and the base currency.
  4. Sign in with the sign-in name and password you chose. You are the administrator; you can create other users.
  5. The first-run form works once. After it, nobody can use it again.

KEEP SAFE
  - C:\ProgramData\DEASys\deasys.conf (connection and sign-in key)
  - C:\ProgramData\DEASys\backups (database backups; they contain every password hash and the audit trail)

BACKUP
  Run from an elevated PowerShell:
      & "C:\Program Files\DEASys\deasys-server.exe" backup "C:\ProgramData\DEASys\backups\manual-$(Get-Date -f yyyyMMdd-HHmm).dump"
  Copy the backup file off this computer as well.

UPGRADE
  Run the new installer, or install.ps1 from the new zip, over the existing installation. Your data is kept. The database
  is backed up first. If the new version fails to start, the old version and its database are put back. The terms are
  asked again only when the new version has a newer terms version.

NETWORK ACCESS
  By default only this computer can open DEASys. To let other computers on your private network open it, choose the
  network option in the installer (or run install.ps1 -AllowNetwork, elevated). Do not expose DEASys to the internet
  without a TLS proxy in front of it.

UNINSTALL
  Settings > Apps > DEASys > Uninstall, or run "C:\Program Files\DEASys\uninstall.ps1" from an elevated PowerShell.
  The uninstaller first prints what it removes (the DEASys service, the firewall rule, shortcuts and the program files)
  and what it keeps. Your data, backups, settings, logs and terms record are kept. To delete them as well, run
  uninstall.ps1 -RemoveData and type the confirmation phrase. PostgreSQL itself is not touched: uninstall it from
  Windows' Apps list if you no longer need it.

LOG FILES
  C:\ProgramData\DEASys\logs\install.log (installer and pre-flight checks), deasys.log (server, rotated).

SUPPORT
  See the support address in the release notes. Include the install.log (it contains no passwords) with any report.
