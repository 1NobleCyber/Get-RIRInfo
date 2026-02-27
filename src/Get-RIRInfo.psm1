# Ensure dependencies are available
Import-Module PSSQLite -ErrorAction Stop

# Initialize internal module variables
$script:dbPath = "$env:USERPROFILE\IPCache.db"

# Load Private Functions
$privateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private" -Filter *.ps1
foreach ($file in $privateFunctions) {
    . $file.FullName
}

# Load Public Functions
$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public" -Filter *.ps1
foreach ($file in $publicFunctions) {
    . $file.FullName
}
