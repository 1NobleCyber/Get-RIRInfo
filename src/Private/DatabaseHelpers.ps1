# Initialize the database
function Initialize-RirDatabase {
    if (-not (Test-Path $script:dbPath)) {
        $query = @"
        CREATE TABLE Cache (
            CIDR TEXT PRIMARY KEY,
            Owner TEXT,
            AbuseContact TEXT,
            Country TEXT,
            Source TEXT,
            LastUpdated TEXT
        )
"@
        Invoke-SqliteQuery -DataSource $script:dbPath -Query $query
    }
}

# Function to get cached entry
function Get-RirCacheEntry {
    param (
        [string]$IPAddress
    )
    $query = "SELECT * FROM Cache"
    # To prevent error if DB not found, initialize if missing
    Initialize-RirDatabase

    $entries = Invoke-SqliteQuery -DataSource $script:dbPath -Query $query
    $entry = $null
    foreach ($row in $entries) {
        $CIDR = $row.CIDR
        if (Test-IpInCidr -IPAddress $IPAddress -CIDR $CIDR) {
            $entry = @{
                CIDR         = $CIDR
                Owner        = $row.Owner
                AbuseContact = $row.AbuseContact
                Country      = $row.Country
                Source       = $row.Source
                LastUpdated  = [datetime]::Parse($row.LastUpdated)
            }
            break
        }
    }
    return $entry
}

# Function to add or update cache entry
function Set-RirCacheEntry {
    param (
        [string]$CIDR,
        [string]$Owner,
        [string]$AbuseContact,
        [string]$Country,
        [string]$Source
    )

    Initialize-RirDatabase

    foreach ($cidrentry in $CIDR.Split(',')) {
        $query = @"
        INSERT OR REPLACE INTO Cache (CIDR, Owner, AbuseContact, Country, Source, LastUpdated)
        VALUES ('$cidrentry', '$Owner', '$AbuseContact', '$Country', '$Source', '$(Get-Date -Format o)')
"@
        Invoke-SqliteQuery -DataSource $script:dbPath -Query $query -ErrorAction Ignore
    }
}
