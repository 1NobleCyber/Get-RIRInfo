function Get-RirIpInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({ ([System.Net.IPAddress]$_).AddressFamily -eq 'InterNetwork' -or ([System.Net.IPAddress]$_).AddressFamily -eq 'InterNetworkV6' })]
        [string]$IPAddress
    )

    begin {
        Initialize-RirDatabase
    }

    process {
        # Check Cache
        $cacheEntry = Get-RirCacheEntry -IPAddress $IPAddress
        if ($cacheEntry -and ($cacheEntry.LastUpdated -gt (Get-Date).AddDays(-90))) {
            Write-Verbose "Returning cached entry for $IPAddress"
            return $cacheEntry
        }

        # Query RDAP
        Write-Verbose "Querying RDAP for $IPAddress"
        $rdapResponse = Invoke-RdapQuery -IPAddress $IPAddress

        if ($rdapResponse) {
            # Parse RDAP JSON into structured hashtable
            $parsedResult = ConvertFrom-RdapResponse -RdapInfo $rdapResponse
            
            # Cache the result
            Set-RirCacheEntry -CIDR $parsedResult.CIDR `
                -Owner $parsedResult.Owner `
                -AbuseContact $parsedResult.AbuseContact `
                -Country $parsedResult.Country `
                -Source $parsedResult.Source

            return $parsedResult
        }
        else {
            Write-Warning "RDAP query failed or returned no data for $IPAddress."
            return @{
                CIDR         = ""
                Owner        = "ERROR"
                AbuseContact = ""
                Country      = ""
                Source       = ""
            }
        }
    }
}
