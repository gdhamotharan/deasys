# Changelog

## v0.1.0 (date: placeholder)

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

## Unreleased (0.1.0 rebuild)
- Optional, unticked "tell the author" box on the terms step; off unless `registration_url` is configured. Terms revised (version `2026-11-10-draft-2`, sections 5.2 and 5.3).
- The installer asks again when the terms text is revised on the same day.
- Starting `deasys-server.exe` with no database configured now prints the steps to create the PostgreSQL database, the complete connection string and the commands to save the settings and start (it no longer prints one terse line). `config init --database-url` writes the database address and the signing key in one step.
- New double-click installer wrapper `Install DEASys.cmd` (asks for administrator rights, keeps the window open). INSTALL.md and README explain that the `.exe` alone is not the installer.
