function Invoke-RdapQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )

    # List of RDAP bootstrap URLs to try
    $rdapUrls = @(
        'https://rdap.arin.net/registry'
        'https://rdap.db.ripe.net'
        'https://rdap.apnic.net'
        'https://rdap.lacnic.net/rdap'
        'https://rdap.afrinic.net/rdap'
    )

    foreach ($baseUrl in $rdapUrls) {
        $url = "$baseUrl/ip/$IPAddress"
        try {
            $response = Invoke-RestMethod -Uri $url -Headers @{ Accept = "application/rdap+json" } -ErrorAction Stop
            if ($response) {
                return $response
            }
        }
        catch {
            # Let it fall through to the next URL on 404 or other errors
            Write-Verbose "RDAP query to $url failed: $_"
        }
    }
    
    return $null
}
