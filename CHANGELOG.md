# Changelog

## v0.2.0-beta.1 (beta, not yet released as a final version)

This is a beta for evaluation and trial use. It is not complete, not certified and not compliant with any statutory requirement.
The feature coverage figures are in [docs/FEATURES.md](docs/FEATURES.md).

**Before you upgrade or install:** PostgreSQL 13 or later is now a prerequisite. The installer no longer installs a database.
Read [INSTALL.md](INSTALL.md) first.

### Changed behaviour

- **PostgreSQL is a prerequisite.** Install PostgreSQL 16 or later (13 is the minimum). The installer asks for the connection, tests it, and writes nothing until the test works. Earlier installs that used the bundled database keep that database.
- **Installer.** The installer shows the terms, asks for the database connection (host, port, database, login and a hidden password), and runs its checks before it changes anything. An unattended install takes the same answers from `DEASYS_DB_*` variables.
- **Sign-in sessions.** A sign-in token lasts 60 minutes. A session ends on sign-out, a password change, a deactivation, or a change of a user's default role or branch.
- **Sign-in throttle.** Failed sign-in attempts are counted before the password is checked, so parallel guesses cannot exceed the limit.
- **Optional voucher rules are off by default.** Rules that a voucher must satisfy (for example, payment details) are opt-in settings. They stay off until an administrator turns them on.
- **Default roles.** A new installation gets role templates for each job: Administrator, CFO, Senior Accountant, Junior Accountant, Checker, Authorizer, Auditor and Viewer. The Auditor role creates and changes nothing. Every route is default-deny: a user needs the permission the route names. See [the guide, section 6.6](USER-GUIDE.md#66-roles-and-permissions).
- **Opening-balance difference.** While the opening balances of the ledgers do not agree, the trial balance, the Schedule III balance sheet and the close checklist show a line "Difference in opening balances". It clears when the openings agree. One-sided openings are still accepted.
- **Connectors are off by default.** Each external connector (GST return, e-invoice, e-way bill, GSTR-2B, Form 26AS, bank payment, bank statement) must be switched on by an administrator and given its settings. None has been verified with any provider.
- **The first-start message.** Starting the program with no database configured prints the steps to create the database and the connection string.

### Added

- **Portal answer files** (`/gst/portal-responses`): upload the e-invoice IRN result, the e-way bill result, the GST return acknowledgement (ARN and date) and the TDS challan CIN as CSV. Each file is checked row by row; rows that fail the checks are listed with their line numbers and the others are applied. These are DEASys's own CSV layouts, not the portals' downloads.
- **Bank response** (`/bank-response`): upload the bank's status file for NEFT payments, with the column and status mapping. Lines that are not applied are listed.
- **GSTR-9 working data** (`/gst/gstr9`): the annual working data as JSON and as one CSV. This is not the portal's offline file.
- **Connector framework** (off by default): test connection, send, cancel and fetch for each connector, with a request log that holds no secrets. Secrets are sealed in the database and never shown again.
- **E-mail of invoices**: the invoice PDF attached, sent through an SMTP server you configure (STARTTLS or TLS; sign-in only on an encrypted connection). Off until configured.
- **Statement and reminder PDFs** on the customer and vendor screens. Plain layout, not mailed.
- **Form 26AS** import also reads the portal's `^`-delimited text layout.
- **Bank statement rules** can be tested against a statement before they are saved; nothing is saved by the test.
- **Payroll file upload** on the integration screens, for the payroll interface (the interface reads a file; DEASys does not compute payroll).

### Fixed

- Parallel requests that create the same ledger name create one ledger, whatever the letter case.
- Data Entry and other roles no longer read the audit trail, the API keys or the webhooks.
- Bank file screens show only the branches the user may see.
- Statement and reminder requests return the rule's own message (for example, a reminder with no overdue invoices) rather than a server error.
- A receipt or payment entered as a voucher against an invoice or bill now settles it.
- The Profit & Loss and Balance Sheet views show their amounts, including the expense side and the profit or loss.
- Debtors Ageing lists the open invoices of customers who owe money.

### Verified

- Server tests (`go test ./...`) on a seeded database: every package passes except two tests with out-of-date expectations (see the README).
- Browser: a receipt and a payment, each entered as a voucher and checked and authorised by separate users, settle a sales invoice and a purchase bill. The trial balance, profit and loss, balance sheet and debtors ageing agree with the postings.
- Fresh install in test mode (no service, no firewall rule) against PostgreSQL 13.6: first run, sign-in, and one voucher posted through maker, checker and authoriser.
- Upgrade in place from 0.1.0 (test mode, PostgreSQL 13.6): the database is backed up first, 27 scripts are applied, and the data, sign-in and balances are unchanged.
- Uninstall with the data kept, and uninstall with the data removed.

### Not verified or not built in this beta

See the known limitations in [the README](README.md#known-limitations).

## v0.1.0 (first public release)

First public release of DEASys: the accounting server with its web interface, for Windows and Linux.

- Installation: Windows installer with bundled PostgreSQL 16 or an existing server; zip with install.ps1; uninstall keeps data unless asked; upgrade backs up first and rolls back on failure.
- First run: six-step first-run wizard in the browser (organisation, first branch, administrator, financial year and currency, review); `init-admin` as a command-line alternative.
- Accounts: double-entry vouchers (journal, payment, receipt, contra, capex, audit, MEE, sales, purchase, credit note, debit note) with maker, checker and authorizer steps and reasons on reject.
- Sales invoices and purchase bills: draft, submit, check, approve, post to ledger, mark as sent, cancel; print view and PDF; attachments (no virus scan).
- Customers and vendors: statements, debtor and creditor ageing, overdue reminders, recurring invoices, GST profile.
- Receipts, payments and credit and debit notes settled against invoices (notes and receipts take a second approval round).
- GST: GSTIN registrations, state codes, tax ledger mapping, HSN and SAC rates, tax on invoices with the GST preview; ITC ledgers, reversals, payment challans and non-payment exceptions; returns data with tie-out, freeze and filed status; filing calendar; late fee and interest calculators; GSTIN check; GSTR-2A and 2B reconciliation; e-invoice and e-way bill payloads with results recorded from an external connector.
- TDS and TCS: rates, parameters, deductor, deductee profiles; deductions on payment vouchers; challans; return data for review; certificates (HTML view); TDS by section; exceptions. Not filing files.
- Cost categories, cost centres, budgets, credit and budget controls.
- Multiple currencies, exchange rates, forex revaluation, interest settings and statement.
- Cheque books, cheque assignment and printing, post-dated cheques.
- Bank upload, bank process, bank reconciliation (BRS), NEFT bank file.
- Reports: financial statements, registers, ageing, cost and budget reports; export to CSV and Excel and print view (HTML and PDF); drill-down; saved reports.
- Day close and year-end close; carry-forward.
- Roles and permissions per screen and action; users; numbering series; audit log (read only).
- Integrations: API keys with scopes and branch limits; inbox; invoice, voucher and TDS imports; masters reads; signed webhooks; screens under Administration.
- Command-line tools: init-admin, migrate, backup, restore, set-password, config, service (Windows).
