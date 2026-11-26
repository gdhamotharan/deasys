# DEASys 0.2.0-beta.1

*Accounts, under control.*

**DEASys** (Double Entry Accounting System) is free double-entry accounting software from Creative Global Financial Solutions. It runs on your own computer (Windows 10 or 11, 64-bit; a Linux program is also published) and you use it in your web browser.

> **This is a beta.** It is for evaluation and trial use alongside your existing records. It is not complete, not certified and not compliant with any tax or statutory requirement. Check every figure with your accountant before you file, pay or sign anything.

## What it does

- Double-entry vouchers, with maker, checker and authorizer steps before anything is posted.
- Sales invoices and purchase bills, approved and then posted to the ledger.
- Customers and vendors, with statements, ageing and reminders.
- Receipts, payments, contra and journal vouchers, settled bill by bill.
- GST on invoices, GSTIN and HSN/SAC rates, input tax credit ledgers, return data with tie-out checks, and reconciliation of GSTR-2A and 2B.
- TDS and TCS on payments, with challans, return data for review, and certificates.
- Branches, cost centres and budgets, with warning or blocking controls.
- Several currencies, exchange rates and forex revaluation.
- Bank statements, bank reconciliation and NEFT payment files.
- Financial statements and reports, exported to CSV, Excel or PDF.
- Day and year close, roles and permissions, and an audit log.
- Connection to other systems through API keys, an inbox and webhooks.

Not included by design: inventory and stock, HR, and payroll computation.

## Coverage

DEASys covers part of our published feature list. The current figures, and the list of what is covered, partly built and not built yet, are in [docs/FEATURES.md](docs/FEATURES.md).

## Install

You need Windows 10 or 11 (64-bit), administrator rights for the installer, **PostgreSQL 16 or later** (PostgreSQL 13 is the minimum), an empty database with its login, and a web browser. The installer installs DEASys only. It does not install PostgreSQL.

[INSTALL.md](INSTALL.md) has the step-by-step guide: the SQL that creates the database, a complete connection string, the installer, upgrading from 0.1.0, and uninstalling.

## Documentation

- [USER-GUIDE.md](USER-GUIDE.md): the full guide, with screenshots.
- [INSTALL.md](INSTALL.md): install, upgrade and uninstall.
- [CHANGELOG.md](CHANGELOG.md): what is new and what changed.
- [docs/FEATURES.md](docs/FEATURES.md): the coverage figures and the feature lists.
- [docs/external-systems.md](docs/external-systems.md): the file option and the API option for each external system.
- [docs/images/INDEX.md](docs/images/INDEX.md): the index of the screenshots.
- [LICENSE.txt](LICENSE.txt), [windows/TERMS.txt](windows/TERMS.txt) and [SUPPORT.md](SUPPORT.md).

## Terms and licence

DEASys is free of charge, including for use in your own business. It is distributed in binary form only; the source code is not published. The licence (`LICENSE.txt`) and the terms (`windows/TERMS.txt`) are drafts awaiting legal review. Read them before you install. The installer shows the terms and asks you to accept them.

## What has been tested

- Windows 10, with PostgreSQL 13.6 and 16.4.
- A fresh install against PostgreSQL 13.6, and a first run.
- An upgrade from 0.1.0 that used its bundled database (PostgreSQL 16.4), with the database backed up first and the pre-upgrade backup restored in a test.
- Uninstall with the data kept, and uninstall with the data removed.

## Known limitations

- **Tested on Windows 10 only,** with PostgreSQL 13.6 and 16.4. Windows 11 has not been tested.
- **Not tested yet:** the Windows Setup wizard (an installer built with Inno Setup is not part of this beta; use `Install DEASys.cmd` or `install.ps1`), the Windows service and firewall steps on an administrator machine, and the Linux program.
- **Performance is not proven.** No load test has been run on a large company.
- **No multi-factor sign-in and no single sign-on.** Sign-in is by user name and password.
- **The audit trail is not tamper-evident.**
- **Approvals are by step, not by amount.** Every voucher goes through the same maker, checker and authorizer steps. Approval thresholds are not built.
- **Not included:** Tally XML import, GSTR-7, GSTR-8, GSTR-9C reconciliation, XBRL export, a user-defined report builder, and languages other than English.
- **TDS files are data only.** The 26Q and 27EQ files are CSV data for review. They are not in the return utility (FVU) format, and DEASys does not file TDS returns.
- **Portal answer files use DEASys's own CSV layouts.** They are not the portals' downloads.
- **Connectors are off by default and are not verified with any provider.** No file DEASys produces has been accepted by a portal, an offline utility or a bank. Use the file option until your adviser or bank has accepted a file.
- **Administrators see all branches and regions** of the company.
- **Partly built or not yet tested:** some GST, TDS, banking, reporting and integration items. See [docs/FEATURES.md](docs/FEATURES.md).
- **DEASys does not file anything for you.** Its tax rates, due dates and file formats are editable defaults that may be out of date or wrong for your case. Check every output with a qualified adviser before you file, pay or sign.

## Support

See [SUPPORT.md](SUPPORT.md).
