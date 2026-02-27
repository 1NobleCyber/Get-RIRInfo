# Helper to convert ISO country code
function Convert-IsoToCountryName {
    param (
        [string]$isoCode
    )
    if ([string]::IsNullOrWhiteSpace($isoCode)) { return $null }
    
    try {
        $regionInfo = New-Object System.Globalization.RegionInfo $isoCode
        return $regionInfo.EnglishName
    }
    catch {
        Write-Verbose "Invalid ISO code: $isoCode"
        return $isoCode
    }
}

# Helper to join CIDR arrays
function Convert-CidrsToString {
    param ($cidrs)
    if ($null -eq $cidrs) { return $null }
    $cidrArray = @()
    foreach ($entry in $cidrs) {
        $cidrArray += "$($entry.v4prefix)/$($entry.length)"
    }
    return $cidrArray -join ','
}

# Generic dispatcher
function ConvertFrom-RdapResponse {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RdapInfo
    )

    # Determine provider
    $provider = $null
    $registrantLink = $($RdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty links)
    
    if ($null -eq $registrantLink) {
        $adminLink = $($RdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty links)
        if ($adminLink) { $provider = $adminLink[0].value }
    }
    else {
        $provider = $registrantLink[0].value
    }
    
    if (-not $provider) {
        # Fallback if no link in registrant/administrative
        $provider = $($RdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty links)[0].value
    }
    
    $providerStr = [string]$provider

    # Dispatch to specific parser based on provider URL
    if ($providerStr -match "arin\.net") {
        return ConvertFrom-RdapArin -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "ripe\.net") {
        return ConvertFrom-RdapRipe -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "jpnic\.rdap\.apnic\.net") {
        return ConvertFrom-RdapJpnic -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "apnic\.net") {
        return ConvertFrom-RdapApnic -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "lacnic\.net") {
        return ConvertFrom-RdapLacnic -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "registro\.br") {
        return ConvertFrom-RdapRegistroBr -rdapInfo $RdapInfo
    }
    elseif ($providerStr -match "afrinic\.net") {
        return ConvertFrom-RdapAfrinic -rdapInfo $RdapInfo
    }

    # Fallback for unrecognized provider or missing specific parser
    Write-Warning "Unrecognized RDAP provider: $providerStr. Attempting generic APNIC-style parse."
    # We can default to APNIC style since it's quite resilient or just return generic
    return ConvertFrom-RdapGeneric -rdapInfo $RdapInfo -sourceStr "Unknown ($providerStr)"
}

function ConvertFrom-RdapArin {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    $owner = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })[3]
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }

    $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })[3]
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }

    $countryObj = $rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'adr' } }
    $country = ''
    if ($countryObj -and $countryObj.Count -ge 2) {
        $country = $countryObj[1].label -split [Environment]::NewLine | Select-Object -Last 1
    }

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'ARIN' }
}

function ConvertFrom-RdapRipe {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    
    $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })[3]
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }

    $handles = $rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty handle
    $owner = $null
    foreach ($handle in $handles) {
        $kind = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'kind' } })[3]
        if ($kind -contains "org") {
            $owner = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })[3]
        }
    }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }
    
    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'RIPE' }
}

function ConvertFrom-RdapJpnic {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    
    $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
    if ($null -eq $abuseContact) {
        $abuseContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
        if ($abuseContactObj) { $abuseContact = $abuseContactObj[0][3] }
    }
    else {
        $abuseContact = $abuseContact[0][3]
    }
    
    $owner = $($rdapInfo.remarks | Select-Object -ExpandProperty description)
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }
    
    $handles = $rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty handle
    foreach ($handle in $handles) {
        $kindObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'kind' } })
        if ($kindObj -and $kindObj[3] -contains "org") {
            $ownerObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })
            if ($ownerObj) { $owner = $ownerObj[3] }
        }
    }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }

    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'JPNIC' }
}

function ConvertFrom-RdapApnic {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    
    $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
    if ($null -ne $abuseContact) {
        if ($abuseContact[0].Length -ne 1) {
            if ($abuseContact[0][0].Length -ne 1) {
                $abuseContact = $abuseContact[0][3]
            }
            else {
                $abuseContact = $abuseContact[3]
            }
        }
    }
    if ($null -ne $abuseContact -and $abuseContact.GetType().Name -eq 'Object[]' -and $abuseContact[0].length -ne 1) {
        $abuseContact = $abuseContact[0]
    }
    if ($null -eq $abuseContact) {
        $adminContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
        if ($adminContactObj -and $adminContactObj.GetType().Name -eq 'Object[]' -and $adminContactObj[0].length -ne 1) {
            $abuseContact = $adminContactObj[3]
        }
    }
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }
    
    $handles = $rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty handle
    $owner = $null
    foreach ($handle in $handles) {
        $kindObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'kind' } })
        if ($kindObj -and $kindObj[3] -contains "org") {
            $ownerObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' -and $_.handle -eq $handle } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })
            if ($ownerObj) { $owner = $ownerObj[3] }
        }
    }
    if ($null -eq $owner) {
        $owner = $($rdapInfo.remarks | Select-Object -ExpandProperty description)
        if ($owner -and $owner.GetType().Name -eq 'Object[]' -and $owner[0].length -ne 1) {
            $owner = $owner[0]
        }
    }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }

    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'APNIC' }
}

function ConvertFrom-RdapLacnic {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    
    $abuseContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
    if ($null -eq $abuseContactObj) {
        $adminContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
        if ($adminContactObj) { $abuseContact = $adminContactObj[3] } else { $abuseContact = $null }
    }
    else {
        $abuseContact = $abuseContactObj[3]
    }
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }
    
    $ownerObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })
    $owner = if ($ownerObj) { $ownerObj[3] } else { $null }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }

    $countryObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'adr' } })
    $countryStr = if ($countryObj -and $countryObj.Count -ge 2) { $countryObj[1].label -split [Environment]::NewLine | Select-Object -Last 1 } else { $rdapInfo.country }
    $country = Convert-IsoToCountryName $countryStr

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'LACNIC' }
}

function ConvertFrom-RdapRegistroBr {
    param ($rdapInfo)
    $cidr = $rdapInfo.handle
    
    $abuseContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
    if ($null -eq $abuseContactObj) {
        $adminContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
        if ($adminContactObj) { $abuseContact = $adminContactObj[3] } else { $abuseContact = $null }
    }
    else {
        $abuseContact = $abuseContactObj[3]
    }
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }
    
    $ownerObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } })
    $owner = if ($ownerObj) { $ownerObj[3] } else { $null }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }
    
    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'NIC.br' }
}

function ConvertFrom-RdapAfrinic {
    param ($rdapInfo)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    
    $abuseContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
    if ($null -eq $abuseContactObj) {
        $adminContactObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } })
        if ($adminContactObj) { $abuseContact = $adminContactObj[3] } else { $abuseContact = $null }
    }
    else {
        $abuseContact = $abuseContactObj[3]
    }
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[0] }
    
    $ownerObj = $rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'adr' } }
    if ($null -eq $ownerObj) {
        $adminAdrObj = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'adr' } })
        if ($adminAdrObj) { $ownerObj = $adminAdrObj[3] } else { $ownerObj = $null }
    }
    else {
        $ownerObj = $ownerObj[3]
    }
    
    $owner = if ($ownerObj) { $ownerObj -split [Environment]::NewLine | Select-Object -First 1 } else { $null }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[0] }

    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = 'AfriNIC' }
}

function ConvertFrom-RdapGeneric {
    param ($rdapInfo, $sourceStr)
    $cidr = Convert-CidrsToString -cidrs $rdapInfo.cidr0_cidrs
    if (-not $cidr) { $cidr = $rdapInfo.handle }

    $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'abuse' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } }) | Select-Object -Last 1
    if (-not $abuseContact) {
        $abuseContact = $($rdapInfo.entities | Where-Object { $_.roles -contains 'administrative' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'email' } }) | Select-Object -Last 1
    }
    if ($abuseContact -and $abuseContact.GetType().Name -eq 'Object[]') { $abuseContact = $abuseContact[-1] }

    $owner = $($rdapInfo.entities | Where-Object { $_.roles -contains 'registrant' } | Select-Object -ExpandProperty vcardArray | ForEach-Object { $_ | Where-Object { $_[0] -eq 'fn' } }) | Select-Object -Last 1
    if (-not $owner) {
        $owner = $($rdapInfo.remarks | Select-Object -ExpandProperty description | Select-Object -First 1)
    }
    if ($owner -and $owner.GetType().Name -eq 'Object[]') { $owner = $owner[-1] }

    $country = Convert-IsoToCountryName $rdapInfo.country

    @{ CIDR = $cidr; Owner = $owner; AbuseContact = $abuseContact; Country = $country; Source = $sourceStr }
}
