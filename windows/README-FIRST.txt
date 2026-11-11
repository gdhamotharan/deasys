DEASYS - READ THIS FIRST
=========================

DEASys is double-entry accounting software that runs on this computer and is used in a web browser.

TERMS AND CONDITIONS
  - The DEASys Terms and Conditions are in TERMS.txt, in the folder of this package and in the program folder
    (C:\Program Files\DEASys\TERMS.txt). Read them. The DEASys Freeware Licence (LICENSE.txt) is part of them, and it is
    the licence of record.
  - You must accept the terms before DEASys is installed. The installer shows them as its licence page: choose
    "I accept" to continue. An install started from PowerShell shows the terms in the console and asks you to type ACCEPT.
    Anything else stops the install and nothing is changed.
  - The acceptance is recorded in C:\ProgramData\DEASys\terms-accepted.json (the version of the terms, the time in UTC,
    your Windows user name, the computer name and how the acceptance was given). It holds no password.
  - The first-run screen in the browser asks you to accept the terms again.
  - A new version of the terms (a newer date on the "Version:" line of TERMS.txt) asks you to accept again, on the next
    install or upgrade and in the browser. An older or the same version does not ask again.
  - An unattended install (-Unattended) works only with -AcceptTerms: that switch is your acceptance.

HOW TO START THE INSTALL
  Unzip the WHOLE package, then double-click "Install DEASys.cmd" and answer Windows' permission question. It runs the
  installer and keeps the window open so every message can be read. (deasys-server.exe alone is NOT the installer: it is
  the program, and it needs a PostgreSQL database. If you start it without one it prints the steps to create the database
  and the complete connection string.) To use your own PostgreSQL, choose "existing" when the installer asks.

BEFORE ANYTHING IS CHANGED
  The installer runs these checks first. If one fails, it stops, says why and changes nothing:
  - it runs with administrator rights (except in -Portable test mode);
  - the drive of the program folder and the drive of the data folder have at least 1.5 GB free (bundled database);
  - the web port (8080) and the database port (5433) are free, unless they are held by the DEASys installation being
    upgraded. If another program holds one, the installer names it;
  - no other Windows service called DEASys or DEASysDB exists (unless this is an upgrade of DEASys);
  - when the PostgreSQL programs must be downloaded, the download address answers (see below).
  It then prints what it will change (folders, services, account, ports, firewall, shortcuts, download) and asks
  "Continue? (type Y to continue)". Unattended installs print the list and go on.

POSTGRESQL DOWNLOAD (ONE TIME)
  If this package has no postgresql folder (the zip build without PostgreSQL), the bundled database needs the PostgreSQL
  16 programs. The installer downloads the pinned PostgreSQL zip once into C:\ProgramData\DEASys\downloads, checks its
  SHA-256 and extracts it into C:\Program Files\DEASys\postgresql. The download needs internet access. If the address
  cannot be reached, the install stops before any change and says what to do instead:
    - put the zip (postgresql-16.4-1-windows-x64-binaries.zip) in C:\ProgramData\DEASys\downloads, or
    - pass -PgBin with the folder that contains initdb.exe, or
    - use an existing PostgreSQL server with -DbMode existing.

WHAT THE INSTALLER DOES
  - Copies the program to C:\Program Files\DEASys.
  - Sets up its own PostgreSQL database (bundled, listens on 127.0.0.1 only, port 5433), unless you chose an existing
    database server.
  - Creates the configuration file C:\ProgramData\DEASys\deasys.conf. It holds the database password and the sign-in
    key: keep it private. Only administrators and the service account can read it.
  - Registers the Windows services "DEASys" (the web server) and "DEASysDB" (the database) to start with Windows. The
    database service runs as the local account DEASysDb, which is not an administrator.
  - Creates Start Menu and desktop shortcuts that open http://localhost:8080.

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
  - C:\ProgramData\DEASys\pgsuper.secret (the database superuser password; administrators only)

BACKUP
  Run from an elevated PowerShell:
      & "C:\Program Files\DEASys\deasys-server.exe" backup "C:\ProgramData\DEASys\backups\manual-$(Get-Date -f yyyyMMdd-HHmm).dump"
  Copy the backup file off this computer as well.

UPGRADE
  Run the new installer, or install.ps1 from the new zip, over the existing installation. Your data is kept. The database
  is backed up first. If the new version fails to start, the old version and its database are put back. The terms are
  asked again only when the new version has a newer terms version.

NETWORK ACCESS
  By default only this computer can open DEASys. To let other computers on your private network open it, run
  install.ps1 -AllowNetwork (elevated). Do not expose DEASys to the internet without a TLS proxy in front of it.

UNINSTALL
  Settings > Apps > DEASys > Uninstall, or run "C:\Program Files\DEASys\uninstall.ps1" from an elevated PowerShell.
  The uninstaller first prints what it removes (services, the DEASysDb account, the firewall rule, shortcuts and the
  program files) and what it keeps. Your data, backups, settings, logs and terms record are kept. To delete them as
  well, run uninstall.ps1 -RemoveData and type the confirmation phrase.

LOG FILES
  C:\ProgramData\DEASys\logs\install.log (installer and pre-flight checks), deasys.log (server, rotated), postgres.log
  (database).

SUPPORT
  See the support address in the release notes. Include the install.log (it contains no passwords) with any report.
