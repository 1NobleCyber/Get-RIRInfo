@{
    RootModule = 'Get-RIRInfo.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'edaa03cf-35a3-4cc0-acfb-a0bda8269739'
    Author = 'David Crawford'
    CompanyName = 'Unknown'
    Copyright = 'Unlicense license'
    Description = 'A PowerShell module for retrieving and parsing IP owner info from Regional/National Internet Registries.'
    PowerShellVersion = '5.1'
    RequiredModules = @('PSSQLite')
    FunctionsToExport = @('Get-RirIpInfo')
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
}
