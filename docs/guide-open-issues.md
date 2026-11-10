# Guide open issues (for the product owner)

Status after the UI update (webtally-ui master daad953, packaging in webtally-core dist-b). Each item names the screen. Items marked **fixed** were checked in the source; items marked **to verify** need a check in the running UI.

## A. Fixed in the product (checked in source)

1. **First-run form in the browser.** Fixed: `setup/FirstRunWizard.tsx` runs before sign-in when no user exists (six steps, Create on the last step).
2. **GST screens.** Fixed for setup, registrations, states, tax ledgers, ITC, challans, reversals, non-payment, returns (tie-out, freeze, filed), calendar, late fee and interest, GSTIN check, 2A/2B reconciliation, and e-invoice and e-way bill data. Limits kept in the guide: no portal filing; e-invoice and e-way bill are built here and sent by an external connector.
3. **TDS masters and operations have screens.** Fixed: Administration > TDS Rates, TDS Parameters, TDS Deductor, Deductee Profiles; Transaction > TDS Deductions, Challans, TDS Return Data, Certificates, TDS by Section, TDS Exceptions.
4. **Integrations, saved reports, export.** Fixed: Administration > Integration Keys, Integration Inbox, Webhooks, How to Connect; Reports > Saved Reports; export format choice (CSV, Excel, Print view HTML and PDF) on reports.
5. **Drill-down.** Fixed: `/reports/drill` (Vouchers Behind a Figure) and statement rows.
7. **Branches (partly).** The first branch is created by the wizard. Centre Master is still read only (`/masters/centres`); branches cannot be added in the UI. See B1.
16. **Invoice register text claiming automatic posting.** Not found in the current source. Fixed as far as the source shows; to verify on `/sales/invoices`.
17. **No posting button label.** Fixed: the invoice action is "Post to ledger" (and "Posted to ledger" after).
18. **Status words.** Fixed: `VOUCHER_STATUS_WORDS` and `INVOICE_STATUS_WORDS` in `src/labels.ts` are the single source.
20. **Centre spelling.** Mostly fixed: NOUNS uses "Centre". Some "Center" remains (for example "Center Name" in Masters). To verify on the screens.
21. **Administration section.** Fixed: the section is titled Administration, not the role name.
22. **Screens missing from the menu.** Fixed: All Vouchers, My Requests and Bulk Transaction are in Transaction; Bank Master and Centre Master are in the Masters section.
23. **Masters index not in the menu.** Fixed: Masters section with `/masters`.
25. **Mock and demo mode.** Fixed for the product build: `MOCK` is true only in the development build (`import.meta.env.DEV`).
19. **Menu label and page title.** Mostly fixed: the menu and page use "User Role Mapping". "Role Master" remains only in NOUNS. To verify.
27. **Transaction hidden for roleId 9.** No such check remains in Layout.tsx. Removed.
32. **Installer.** Partly fixed: the packaging folder exists (Inno Setup installer, zip with install.ps1, uninstall.ps1, README-FIRST.txt). `LICENSE.txt` is copied from packaging and is a **draft for legal review, not yet approved for release**. The guide describes the installer; see D1 for the remaining placeholders.
34. **Figure numbers in the text.** Fixed: the README no longer uses figure numbers; the index uses file names.

## B. Still open (missing or limited in the product)

1. **Branches cannot be added or edited in the UI.** Centre Master is read only. Only the first-run wizard creates a branch.
2. **No screen for backup and restore.** Commands only (`deasys-server backup|restore`). The installer README gives the backup command.
3. **Opening balances.** No screen or documented route. The guide says to confirm the method with the administrator.
4. **Receipts and credit and debit notes take a second approval round.** Notes and receipts still post a Draft voucher at approval (unfinished-features.md item 11). Make it one authorize step.
5. **Cancelling a posted invoice** posts a draft reversal that goes through the voucher workflow again (item 12).
6. **Audit gaps.** Not logged: entity-bank mapping, GST rate changes, ledger request approve and reject. Drafts are not logged, by design.
7. **Attachments have no antivirus scan** (server README). Block external uploads until antivirus protection is in place.
8. **Reports marked "Not available yet"** (SSRS rows and unported stored procedures). unfinished-features.md items 2 to 5 say to hide them. Not verified in this pass whether they are still listed.
9. **The voucher type numbered 5 (voucher_type 5)** has no menu entry.
10. **Two kinds of voucher forms.** Receipt, payment and contra have purpose-built forms; the other types use the line grid. Explain on screen which to use.
11. **Roles seeded with legacy names** (CFO, AGM, Sr.Manager, Senior Accountant, Junior Accountant, Data Entry Level, Audit). No Viewer role and no maker, checker or approver role. The demo users use these roles.
12. **Next steps is not in the menu.** `/next-steps` is reachable only by its address. Add a menu item or a link from Home.
13. **Next steps says there is no TDS master screen** ("There is no TDS master screen in this release"). That is now wrong: the TDS Rates, Parameters, Deductor and Deductee Profiles screens exist. Fix the text.
14. **Installation-specific residue (fixed).** The reference installation's company name, bank-file remark, e-mail address, weak-password entries and company-filter alias were removed from the product; the binaries and the package were checked and contain none of them.
15. **Owner claims not verified:** "130+ reports" was not counted. The summary uses "many reports". Count the report catalogue after the stale rows are removed.
16. **Customer and vendor form field labels** were not captured in this pass. Check `/sales/customers/new`.

## C. Documentation and configuration

17. **Default port.** The server docs and the installer use 8080 (app) and 5433 (bundled database). docs/integration-guide.md uses `http://localhost:5080`, which is now also in the UI "How to Connect" page text. Fix the guide text to 8080.
18. **The server README has no GST section.** The GST routes (`/api/v1/gst/...`) are documented only in code. Add a GST section to server-go/README.md.
19. **Stale "not in this server yet" lines** in server-go/README.md "Known differences" (unfinished-features.md section 4).
20. **TDS defaults.** Section numbers, rates and thresholds are defaults to be verified by a tax adviser (migration 057). The Income-tax Act 2025 renumbers them from 1 April 2026.
21. **Licence is a draft for legal review.** LICENSE.txt says "DRAFT FOR LEGAL REVIEW - NOT YET APPROVED FOR RELEASE". Do not publish until approved.
22. **Release placeholders.** RELEASE-NOTES.template.md still has `{{VERSION}}`, `{{DATE}}`, `{{COMMIT}}`, `{{SHA256SUMS}}` and the "What is new" and "Known limitations" lists. SUPPORT.md names no support address yet. TESTING.md is referred to by the task but was not present in the packaging folder.
23. **Installer images.** Screens 10 and 11 need a capture of the installer built from the release; the README has no caption for installer pages beyond the first two.

## D. Packaging notes for the release

1. **Zip route wording.** README-FIRST.txt says the first-run form is shown at `http://localhost:8080`; the guide matches. No change needed.
2. **Uninstall confirmation** is typed exactly: `DELETE DEASYS DATA` (uninstall.ps1 `-RemoveData`).
3. **Unsigned builds** show a SmartScreen warning; the release notes must say so (RELEASE-NOTES.template.md already does).

## E. Screenshot capture notes

- Screens that may not exist in the running UI: 19 (Centre Master add: read only, so capture the list), 26 (User Role Mapping), 107 (day-closed message), 96 (password reset in the user dialog). Each has a fallback in the manifest notes.
- Next steps (115) is reached by address; capture it that way.
- Installer (10, 11) depends on the built installer.
- The viewer demo user's role must be verified before capture.
