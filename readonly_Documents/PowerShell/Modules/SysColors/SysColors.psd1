@{
    RootModule        = 'SysColors.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8f07c0da-33a9-4c7b-bce7-a4c5eac0d6cd'
    Author            = 'Dotfiles Automation'
    CompanyName       = 'dotfiles'
    Copyright         = '(c) Dotfiles. All rights reserved.'
    Description       = 'Applies color themes defined in YAML across Windows, WSL, and editors.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('SysColors', 'SysColors-List', 'SysColors-Where', 'SysColors-Restore')
    CmdletsToExport   = @()
    AliasesToExport   = @()
    PrivateData       = @{}
}
