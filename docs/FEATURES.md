# What DEASys covers

**Covers 116 of 222 features on our published list** (built and tested).

- Built, but not yet tested, or partly built: 80 (17 built but not tested, 63 partly built).
- Not built yet: 26.

These figures were measured in the release check of 0.2.0-beta.1 against the published list of 222 features. Only this file holds the figures; the other documents refer here.

The percentage of features built and tested is 52.3 per cent. Features counted as built and tested are only those a recorded test run has passed on the current code.

## Covered (built and tested)

- **Accounting:** chart of account groups and ledgers, journal, payment, receipt and contra vouchers, sales and purchase invoices posted to the ledger, reversing entries, custom voucher types, voucher history, numbering by branch, consolidated reports across branches.
- **Controls:** maker, checker and authoriser on every voucher, with rejection and resubmission; the creator cannot approve their own voucher; role permissions with default deny; sign-in lockout and token checks.
- **Receivables and payables:** customer and vendor parties with GST details, credit limits with block or warning, debit and credit notes, reverse-charge purchases, vendor payments.
- **GST:** registrations, HSN and SAC rates, CGST, SGST, UTGST, IGST and cess, place of supply, deemed exports, reverse charge, GST on advances, input tax credit ledgers, GST registers, reconciliation summary, due dates, late fee and interest calculators, invoice-furnishing facility.
- **TDS:** rates and thresholds, deduction on payments, challans, late-deduction interest.
- **Banking:** bank accounts, cheque books, cheque printing, post-dated cheque register, bank statement upload from a workbook.
- **Fixed assets:** asset types and depreciation journals.
- **Period end:** day close, year close and carry-forward, prepaid and deferred schedules, accruals that reverse, recurring journals, allocation journals, year-end checklist.
- **Reporting:** trial balance, day book, ledger view, report sets, Excel, CSV and PDF export, comparative reports, exception reports, Schedule III ratios.
- **Multi-currency:** currency and exchange-rate masters, foreign-currency vouchers, revaluation, refusal when a rate is missing.
- **Cost centres and budgets:** cost centres, allocation, cost-centre reports, budget variance, warning and blocking over budget.
- **Integration:** voucher and invoice import API, API keys with scopes, webhook subscriptions.
- **Security:** token checks, sign-in throttling, branch isolation of drafts and ledgers, secrets not shown, password hashing, input validation.
- **Operations:** fresh install and first run, idempotent requests.

## Partly built, or built but not yet tested

- **Accounting and controls:** one-sided opening balances are accepted (the trial balance shows the difference); memo, optional and post-dated vouchers not tested; the edit guard on posted entries not tested; scenario reports not built.
- **Receivables and payables:** receipts and payments against foreign-currency invoices cannot be settled yet; invoice e-mail, invoice attachments, recurring invoices, invoice PDF and print, generic debtors and creditors ageing, gap-free invoice numbers, payment terms, write-offs (still posted as drafts).
- **GST:** ISD and TDS deductor registrations, GSTR-1A amendments, composition return, blocked credits, the 180-day rule, set-off order, GSTR-9 full tables, cancellation of an e-invoice, e-way bill transmission. Filing to the GST portal through the API connector is not verified with any provider; the file options work.
- **TDS and TCS:** Form 16A and the TDS receivable register: TDS on a receipt entered as a voucher is not added to the TDS receivable register. Form 27Q and TCS collection and returns are built but not tested; Form 26Q filing through an API is not available. TDS reports under Reports are not available; use the TDS screens.
- **Banking:** MT940 and CAMT.053 statements are built but not tested through the upload; auto-matching rules and reconciliation changed after the last test run and need a new run; bank file layouts per bank and the NEFT file need a new run; connected banking (statement fetch) needs a provider; payment advice not built.
- **Fixed assets:** revaluation not tested; the Companies Act depreciation method is not separate.
- **Period end:** provisions only through accruals, with no provision register.
- **Reporting:** the Profit & Loss Financial Report shows its heading only; the profit and loss and balance sheet multi-column views are not yet tested as a whole; Schedule III presentation shows Duties & Taxes netted; the Category Analysis reports need a category master that a new install lacks; the credit sales register is empty; not every report runs cleanly in the test suite (the statement variants). Cash flow is tested but funds flow is not; drill-down, saved reports, screen dashboards for receivables and payables, invoice print, statements of accounts and reminder letters (blocked tests), report PDF for every report.
- **Integration:** webhook delivery and redelivery (the delivery check in the test suite fails); payroll file upload from the screen (added after the test run), integration inbox retry and dismiss, WhatsApp and e-mail sending beyond statements and reminders, Excel voucher drafts cannot be reopened to submit.
- **Operations and user interface:** backup and restore not tested end to end, structured logs untested, installer needs a new run after it started to require an existing PostgreSQL, migrations 033 and 034 not tested on an empty or upgraded database, OpenAPI document and its test stale, keyboard use, accessibility and mobile layout not audited, browser suites partly run.

## Not built yet

- **Accounting and controls:** scenario management, approval thresholds with levels and delegation, segregation-of-duties report, nightly integrity job, tamper-evident audit, access reviews, multi-factor sign-in, single sign-on.
- **GST:** bill of supply, GSTR-7 and GSTR-8, GSTR-9C reconciliation.
- **TDS:** professional tax, tax-audit data.
- **Banking:** cash forecast.
- **Reporting:** configurable report columns, scheduled report e-mail, XBRL export, user-defined report builder.
- **Integration:** Tally XML import, WhatsApp sending.
- **Operations and user interface:** metrics and tracing, load test on large data, zero-downtime migrations, rate limits outside sign-in, internationalisation, encryption and TLS evidence.

Inventory, stock, HR and payroll computation are out of scope. DEASys takes payroll totals as a file; it does not compute payroll.
