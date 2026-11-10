# Pinned PostgreSQL binaries for the bundled database. Read by fetch-postgres.ps1.
# SHA-256 recorded 2026-11-10 from a download of this exact URL (338,727,828 bytes).
# It is NOT copied from an official EnterpriseDB checksum page: before a public release, compare it with the official download page (https://www.postgresql.org/download/windows/ or EnterpriseDB) and update this file if the version changes.
# fetch-postgres.ps1 refuses to run while Sha256 is a placeholder.
@{
    Product   = 'PostgreSQL'
    Major     = '16'
    Version   = '16.4-1'
    FileName  = 'postgresql-16.4-1-windows-x64-binaries.zip'
    Url       = 'https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64-binaries.zip'
    Sha256    = '3508d8f085bc3980f38211a82e3f31e5fcae9952105d3dc2f8be67b64a822baa'
    # the zip has one top folder, pgsql\, with bin, lib and share
    TopFolder = 'pgsql'
    License   = 'PostgreSQL License (https://www.postgresql.org/about/licence/). Bundled unchanged.'
}
