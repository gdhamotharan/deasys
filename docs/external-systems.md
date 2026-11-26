# External systems: file option and API option

DEASys works with several systems outside it: government portals, the e-invoice registry, the e-way bill system, banks and
a mail server. For each one there are two ways to exchange data:

- **File option (always available):** DEASys produces a file that you download and upload to the portal or bank yourself.
  Where the portal or bank sends a response, you upload that response file back into DEASys.
- **API option (off by default):** an administrator switches on a connector, gives it the provider's address and
  credentials, and DEASys sends or fetches through it.

**Nothing has been verified with a real portal, utility, bank or mail server.** No file DEASys produces has been accepted by
a portal, the offline utility, the FVU utility or a bank. The connectors use placeholder paths and have not been tested
against any provider. Treat every file as unverified until your tax adviser or your bank has accepted it.

| System | File option: DEASys produces | File option: you upload back | API option (off by default) |
|---|---|---|---|
| GST returns GSTR-1, GSTR-1A, GSTR-3B, GSTR-4 | JSON for the offline utility, and CSV per table | Acknowledgement file (ARN and date), or the ARN typed in | Connector built; the path is a placeholder |
| GSTR-9 | Working data (JSON and one CSV). Not the portal's offline file | Not available | Not available |
| GSTR-2A and 2B | Nothing: you download the JSON from the portal | The portal's JSON is imported to reconcile | Fetch built; the fetched JSON is imported the same way |
| E-invoice (IRP) | Payload per invoice and the pending list | IRN result CSV (invoice number, IRN, acknowledgement number and date, signed QR) | Send and cancel built; placeholder paths |
| E-way bill | Part A and Part B payload per invoice | E-way bill result CSV (invoice number, EWB number and dates) | Send and cancel built; placeholder paths |
| Form 26AS | Nothing: you download it from TRACES | The portal's text file, or DEASys's CSV | Fetch built |
| TDS return 26Q | A CSV data set, labelled as data only, not for filing | Challan CIN file (BSR code, serial, deposit date, CIN) | Not available |
| TCS return 27EQ | A CSV data set, labelled as data only, not for filing | Challan CIN file (as for 26Q) | Not available |
| Bank payments (NEFT) | A file in each bank's layout, and a NEFT CSV | The bank's status file, mapped on the Bank response screen | Send and fetch built; placeholder paths |
| Bank statements | Nothing: you download the statement from the bank | The statement file is imported | Fetch built |
| E-mail of invoices | The invoice PDF | Not applicable | Sends through your SMTP server (not a connector) |
| Statements and reminders | PDF (plain layout) | Not applicable | Not mailed |

## Things to know

- **The portal response files use DEASys's own CSV layouts** for the e-invoice, e-way bill, GST acknowledgement and challan CIN
  files. They are not the portals' own downloads. The header columns are listed on the Portal answer files screen.
- **TDS files are data only.** The 26Q and 27EQ CSVs are not in the return utility (FVU) text format, and DEASys does not
  file TDS returns.
- **Connectors need settings and secrets.** Each connector needs an address that must be https, and its authentication.
  Secrets are sealed in the database and never shown again. Each send, cancel, fetch and test writes one row to the
  request log, without secrets.
- **Connector errors name the file option.** When a connector fails, DEASys says what to do with the file option instead.

Check every file with your accountant or the bank before you rely on it.
