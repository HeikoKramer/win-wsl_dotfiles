#requires -Version 5.1
<#!
.SYNOPSIS
    Theme application helpers for the Windows + WSL dotfiles repository.

.DESCRIPTION
    The SysColors module discovers YAML-based theme definitions, turns them into
    execution plans, and applies the requested updates across multiple targets
    (Windows Terminal, PowerShell, Bash, accent colors, editors, etc.).  Each
    execution plan is idempotent and stores a backup before making changes so
    themes can be reverted with `SysColors-Restore`.

    The module intentionally keeps its public surface area small.  Most of the
    heavy lifting happens in internal helper functions that massage the theme
    data into small plan steps.  A plan step is simply a `PSCustomObject` with a
    target name, the destination path, arbitrary metadata, and an `Apply`
    scriptblock used to update the target.

.NOTES
    Themes rely on the `powershell-yaml` module.  Install it with:

        Install-Module powershell-yaml

    The module is cross-platform but naturally performs best on Windows where
    all targets are available.

#>

Set-StrictMode -Version Latest

$script:ModuleRoot         = Split-Path -Path $PSCommandPath -Parent
$script:ThemeDirectoryName = 'themes'
$script:BackupDirectory    = Join-Path -Path $script:ModuleRoot -ChildPath 'backups'
$script:YamlModuleLoaded   = $false

function Use-SysColorsYamlModule {
    if ($script:YamlModuleLoaded) { return }

    if (-not (Get-Command -Name 'ConvertFrom-Yaml' -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
            throw "The 'powershell-yaml' module is required. Install it with Install-Module powershell-yaml."
        }

        Import-Module -Name 'powershell-yaml' -ErrorAction Stop | Out-Null
    }

    $script:YamlModuleLoaded = $true
}

function Get-SysColorsThemeDirectories {
    param(
        [string[]]$Additional
    )

    $directories = @()

    if ($env:SYSCOLORS_THEME_PATH) {
        $directories += $env:SYSCOLORS_THEME_PATH -split [IO.Path]::PathSeparator
    }

    $directories += Join-Path -Path $script:ModuleRoot -ChildPath $script:ThemeDirectoryName

    if ($Additional) { $directories += $Additional }

    $directories
        | Where-Object { $_ }
        | ForEach-Object { (Resolve-Path -Path $_ -ErrorAction SilentlyContinue) }
        | ForEach-Object { $_.ProviderPath }
        | Sort-Object -Unique
}

function Expand-SysColorsPath {
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)

    if ($expanded -like '~*') {
        $expanded = $expanded -replace '^~', [Environment]::GetFolderPath('UserProfile')
    }

    if ($expanded -like '/*' -or $expanded -like '\\*') { return $expanded }

    $expanded
}

function Resolve-SysColorsThemePath {
    param(
        [string]$Name,
        [string]$Path,
        [string[]]$AdditionalDirectories
    )

    if ($Path) {
        $resolved = Resolve-Path -Path $Path -ErrorAction Stop
        return $resolved.ProviderPath
    }

    if (-not $Name) {
        throw "Specify a theme name or explicit path."
    }

    $searchDirectories = Get-SysColorsThemeDirectories -Additional $AdditionalDirectories

    foreach ($directory in $searchDirectories) {
        foreach ($extension in @('yml', 'yaml')) {
            $candidate = Join-Path -Path $directory -ChildPath "$Name.$extension"
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
            }
        }
    }

    throw "Theme '$Name' was not found in: $($searchDirectories -join ', ')"
}

function Import-SysColorsTheme {
    param(
        [string]$Name,
        [string]$Path,
        [string[]]$AdditionalDirectories
    )

    Use-SysColorsYamlModule
    $resolvedPath = Resolve-SysColorsThemePath -Name $Name -Path $Path -AdditionalDirectories $AdditionalDirectories
    $raw          = Get-Content -LiteralPath $resolvedPath -Raw
    $data         = ConvertFrom-Yaml -Yaml $raw

    [pscustomobject]@{
        Name        = if ($data.name) { [string]$data.name } else { [IO.Path]::GetFileNameWithoutExtension($resolvedPath) }
        Description = [string]$data.description
        Metadata    = $data.metadata
        Targets     = $data.targets
        Raw         = $data
        Source      = $resolvedPath
    }
}

function Get-SysColorsThemeSummary {
    param(
        [IO.FileInfo]$File
    )

    Use-SysColorsYamlModule

    try {
        $raw  = Get-Content -LiteralPath $File.FullName -Raw
        $data = ConvertFrom-Yaml -Yaml $raw
    } catch {
        return [pscustomobject]@{
            Name        = $File.BaseName
            Description = '[Failed to parse]'
            Source      = $File.FullName
            Tags        = @()
            Targets     = @()
        }
    }

    $targets = @()
    if ($null -ne $data.targets) {
        if ($data.targets -is [System.Collections.IDictionary]) {
            $targets = @($data.targets.Keys)
        } elseif ($data.targets -is [System.Collections.IEnumerable] -and $data.targets -isnot [string]) {
            $targets = @($data.targets | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
        } else {
            $targets = @($data.targets.PSObject.Properties.Name)
        }
    }

    [pscustomobject]@{
        Name        = if ($data.name) { [string]$data.name } else { $File.BaseName }
        Description = [string]$data.description
        Tags        = @($data.tags)
        Source      = $File.FullName
        Targets     = $targets
    }
}

function SysColors-List {
    [CmdletBinding()]
    param(
        [string[]]$Directory,
        [switch]$Detailed
    )

    $directories = Get-SysColorsThemeDirectories -Additional $Directory
    $results = @()

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $results += Get-ChildItem -LiteralPath $dir -Filter '*.yml' -File -ErrorAction SilentlyContinue
        $results += Get-ChildItem -LiteralPath $dir -Filter '*.yaml' -File -ErrorAction SilentlyContinue
    }

    $summaries = $results | Sort-Object FullName -Unique | ForEach-Object { Get-SysColorsThemeSummary -File $_ }

    if ($Detailed) {
        foreach ($summary in $summaries) {
            $theme = Import-SysColorsTheme -Path $summary.Source
            $summary | Add-Member -NotePropertyName 'Metadata' -NotePropertyValue $theme.Metadata -Force
            $summary | Add-Member -NotePropertyName 'Raw' -NotePropertyValue $theme.Raw -Force
        }
    }

    $summaries
}

function SysColors-Where {
    [CmdletBinding(DefaultParameterSetName='Text')]
    param(
        [Parameter(ParameterSetName='Text', Position=0)] [string]$Text,
        [Parameter(ParameterSetName='Text')] [string]$Property = 'Name',
        [Parameter(ParameterSetName='Filter', Mandatory, Position=0)] [scriptblock]$Filter,
        [string[]]$Directory,
        [switch]$Detailed
    )

    $themes = SysColors-List -Directory $Directory -Detailed:$Detailed

    if ($PSCmdlet.ParameterSetName -eq 'Filter') {
        return $themes | Where-Object $Filter
    }

    if (-not $Text) { return $themes }

    $themes | Where-Object {
        $value = $_.$Property
        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            return $value -like "*$Text*"
        }

        $value -like "*$Text*"
    }
}

function New-SysColorsPlanStep {
    param(
        [string]$Name,
        [string]$Target,
        [string]$Path,
        [hashtable]$Metadata,
        [scriptblock]$Apply
    )

    [pscustomobject]@{
        Name     = $Name
        Target   = $Target
        Path     = $Path
        Metadata = $Metadata
        Apply    = $Apply
    }
}

function Get-SysColorsBackupPath {
    param(
        [Parameter(Mandatory)] [datetime]$Timestamp
    )

    $directory = Join-Path -Path $script:BackupDirectory -ChildPath ($Timestamp.ToString('yyyyMMdd-HHmmss'))
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $directory
}

function Save-SysColorsManifest {
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable]$Entries,
        [Parameter(Mandatory)] [string]$Destination
    )

    $json = $Entries | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath (Join-Path -Path $Destination -ChildPath 'manifest.json') -Value $json -Encoding UTF8
}

function New-SysColorsBackup {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $relative = $Path -replace '^[A-Za-z]:' -replace '^\\+',''
    $relative = $relative -replace ':', '_'
    $relative = $relative -replace '\\', '/' -replace '\\', '/'

    $destination = Join-Path -Path $DestinationRoot -ChildPath $relative
    $destDir     = Split-Path -Path $destination -Parent

    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $Path -Destination $destination -Force
    return $destination
}

function Invoke-SysColorsPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable]$Plan,
        [switch]$WhatIf,
        [switch]$SkipBackup
    )

    $planItems = @($Plan)
    if (-not $planItems) {
        Write-Warning 'No plan steps were generated.'
        return @()
    }

    $timestamp  = $null
    $backupPath = $null

    if (-not $WhatIf -and -not $SkipBackup) {
        $timestamp  = Get-Date
        $backupPath = Get-SysColorsBackupPath -Timestamp $timestamp
    }
    $manifestItems = @()

    foreach ($step in $planItems) {
        Write-Verbose ("Applying step '{0}' to '{1}'" -f $step.Name, $step.Path)

        if (-not $WhatIf) {
            if (-not $SkipBackup) {
                $backup = New-SysColorsBackup -Path $step.Path -DestinationRoot $backupPath
                $manifestItems += [pscustomobject]@{
                    Target     = $step.Target
                    Path       = $step.Path
                    BackupPath = $backup
                }
            }

            if ($step.Apply) {
                & $step.Apply $step
            }
        }
    }

    if ($backupPath) {
        Save-SysColorsManifest -Entries $manifestItems -Destination $backupPath
    }

    [pscustomobject]@{
        Timestamp  = $timestamp
        BackupPath = $backupPath
        Steps      = $planItems
    }
}

function Get-SysColorsBackups {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:BackupDirectory)) { return @() }

    Get-ChildItem -LiteralPath $script:BackupDirectory -Directory | Sort-Object Name -Descending | ForEach-Object {
        $manifestPath = Join-Path -Path $_.FullName -ChildPath 'manifest.json'
        $manifest     = @()

        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            } catch {}
        }

        [pscustomobject]@{
            Name        = $_.Name
            Path        = $_.FullName
            Timestamp   = [datetime]::ParseExact($_.Name, 'yyyyMMdd-HHmmss', $null)
            Manifest    = $manifest
            Description = if ($manifest) { ($manifest | ForEach-Object { $_.Target }) -join ', ' } else { '' }
        }
    }
}

function Restore-SysColorsBackupSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject]$Backup,
        [switch]$WhatIf
    )

    if (-not $Backup.Manifest) {
        throw "The backup located at '$($Backup.Path)' does not contain a manifest.json file."
    }

    foreach ($entry in $Backup.Manifest) {
        if (-not $entry.BackupPath) { continue }
        if (-not (Test-Path -LiteralPath $entry.BackupPath)) { continue }

        $destination = $entry.Path
        $destDir     = Split-Path -Path $destination -Parent

        if (-not (Test-Path -LiteralPath $destDir)) {
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
        }

        if (-not $WhatIf) {
            Copy-Item -LiteralPath $entry.BackupPath -Destination $destination -Force
        }
    }
}

function New-SysColorsWindowsTerminalStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.windowsTerminal
    if (-not $config) { return @() }

    $settingsPath = $config.settingsPath
    if (-not $settingsPath) {
        $settingsPath = '%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    }
    $path = Expand-SysColorsPath -Path $settingsPath

    $apply = {
        param($step)
        if (-not (Test-Path -LiteralPath $step.Path)) {
            Write-Warning "Windows Terminal settings file '$($step.Path)' was not found."
            return
        }

        $json = Get-Content -LiteralPath $step.Path -Raw | ConvertFrom-Json -Depth 100

        $scheme = $step.Metadata.Scheme
        if ($scheme) {
            $json.schemes = @($json.schemes | Where-Object { $_.name -ne $scheme.name })
            $json.schemes += $scheme
        }

        if ($step.Metadata.Defaults) {
            if (-not $json.profiles) { $json | Add-Member -MemberType NoteProperty -Name 'profiles' -Value (@{}) }
            if (-not $json.profiles.defaults) { $json.profiles | Add-Member -MemberType NoteProperty -Name 'defaults' -Value (@{}) }

            foreach ($property in $step.Metadata.Defaults.Keys) {
                $json.profiles.defaults.$property = $step.Metadata.Defaults[$property]
            }
        }

        if ($step.Metadata.Profiles) {
            foreach ($profile in $step.Metadata.Profiles) {
                if (-not $json.profiles) { continue }
                $existing = $json.profiles.list | Where-Object { $_.name -eq $profile.Name -or $_.source -eq $profile.Source }
                foreach ($item in $existing) {
                    foreach ($property in $profile.Keys) {
                        if ($property -eq 'Name' -or $property -eq 'Source') { continue }
                        $item.$property = $profile[$property]
                    }
                }
            }
        }

        $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $step.Path -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'Windows Terminal' -Target 'WindowsTerminal' -Path $path -Metadata ([ordered]@{
        Scheme   = $config.scheme
        Defaults = $config.profileDefaults
        Profiles = $config.profiles
    }) -Apply $apply
}

function New-SysColorsPowerShellProfileStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.powershell
    if (-not $config) { return @() }

    $pathValue = $config.path
    if (-not $pathValue) {
        $pathValue = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    $path    = Expand-SysColorsPath -Path $pathValue

    $marker = $config.marker
    if (-not $marker) { $marker = '#region SysColors' }

    $endMark = $config.endMarker
    if (-not $endMark) { $endMark = '#endregion SysColors' }
    $content = $config.block

    if (-not $content) { return @() }

    $apply = {
        param($step)
        $content = $step.Metadata.Block

        $existing = ''
        if (Test-Path -LiteralPath $step.Path) {
            $existing = Get-Content -LiteralPath $step.Path -Raw
        }

        $pattern = [regex]::Escape($step.Metadata.Marker) + '.*?' + [regex]::Escape($step.Metadata.EndMarker)
        if ([string]::IsNullOrWhiteSpace($existing)) {
            $newContent = "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker
        } elseif ($existing -match $pattern) {
            $newContent = [regex]::Replace($existing, $pattern, "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker, 'Singleline')
        } else {
            $newContent = $existing.TrimEnd() + "`n`n" + "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker
        }

        Set-Content -LiteralPath $step.Path -Value $newContent -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'PowerShell profile block' -Target 'PowerShell' -Path $path -Metadata ([ordered]@{
        Marker    = $marker
        EndMarker = $endMark
        Block     = $content
    }) -Apply $apply
}

function New-SysColorsBashStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.bash
    if (-not $config) { return @() }

    $pathValue = $config.path
    if (-not $pathValue) { $pathValue = '~/.bashrc' }
    $path    = Expand-SysColorsPath -Path $pathValue

    $marker = $config.marker
    if (-not $marker) { $marker = '# >>> SysColors >>>' }

    $endMark = $config.endMarker
    if (-not $endMark) { $endMark = '# <<< SysColors <<<' }
    $content = $config.block

    if (-not $content) { return @() }

    $apply = {
        param($step)
        $content = $step.Metadata.Block
        $existing = ''
        if (Test-Path -LiteralPath $step.Path) {
            $existing = Get-Content -LiteralPath $step.Path -Raw
        }

        $pattern = [regex]::Escape($step.Metadata.Marker) + '.*?' + [regex]::Escape($step.Metadata.EndMarker)
        if ([string]::IsNullOrWhiteSpace($existing)) {
            $newContent = "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker
        } elseif ($existing -match $pattern) {
            $newContent = [regex]::Replace($existing, $pattern, "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker, 'Singleline')
        } else {
            $newContent = $existing.TrimEnd() + "`n`n" + "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $content.TrimEnd(), $step.Metadata.EndMarker
        }

        Set-Content -LiteralPath $step.Path -Value $newContent -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'Bash profile block' -Target 'Bash' -Path $path -Metadata ([ordered]@{
        Marker    = $marker
        EndMarker = $endMark
        Block     = $content
    }) -Apply $apply
}

function New-SysColorsWindowsAccentStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.windows
    if (-not $config) { return @() }

    if (-not $IsWindows) {
        Write-Verbose 'Skipping Windows accent updates because the host OS is not Windows.'
        return @()
    }

    $apply = {
        param($step)
        if ($step.Metadata.AccentColor) {
            $color = $step.Metadata.AccentColor
            if ($color -is [string] -and $color -match '^#?[0-9A-Fa-f]{6,8}$') {
                $hex = $color.TrimStart('#')
                if ($hex.Length -eq 6) { $hex = 'FF' + $hex }
                $value = [uint32]::Parse($hex, [System.Globalization.NumberStyles]::HexNumber)
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'ColorizationColor' -Value $value -ErrorAction SilentlyContinue
            }
        }

        $wallpaper = $step.Metadata.Wallpaper
        if ($null -ne $wallpaper -and -not [string]::IsNullOrWhiteSpace($wallpaper)) {
            $path = Expand-SysColorsPath -Path $wallpaper
            if (Test-Path -LiteralPath $path) {
                rundll32.exe user32.dll, UpdatePerUserSystemParameters 1, True
                Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value $path -ErrorAction SilentlyContinue
            }
        }
    }

    New-SysColorsPlanStep -Name 'Windows accent & wallpaper' -Target 'Windows' -Path 'HKCU' -Metadata ([ordered]@{
        AccentColor = $config.accentColor
        Wallpaper   = $config.wallpaper
    }) -Apply $apply
}

function New-SysColorsVSCodeStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.vscode
    if (-not $config) { return @() }

    $settingsPath = $config.settingsPath
    if (-not $settingsPath) {
        $settingsPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Code\User\settings.json'
    }
    $path = Expand-SysColorsPath -Path $settingsPath

    $apply = {
        param($step)
        if (-not (Test-Path -LiteralPath $step.Path)) {
            Write-Warning "VS Code settings.json '$($step.Path)' was not found."
            return
        }

        $json = Get-Content -LiteralPath $step.Path -Raw
        $data = if ($json) { ConvertFrom-Json -InputObject $json -Depth 100 } else { @{} }

        if ($step.Metadata.Theme) {
            $data.'workbench.colorTheme' = $step.Metadata.Theme
        }

        if ($step.Metadata.ColorCustomizations) {
            $data.'workbench.colorCustomizations' = $step.Metadata.ColorCustomizations
        }

        if ($step.Metadata.TokenColorCustomizations) {
            $data.'editor.tokenColorCustomizations' = $step.Metadata.TokenColorCustomizations
        }

        $data | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $step.Path -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'VS Code settings' -Target 'VSCode' -Path $path -Metadata ([ordered]@{
        Theme                    = $config.theme
        ColorCustomizations      = $config.colorCustomizations
        TokenColorCustomizations = $config.tokenColorCustomizations
    }) -Apply $apply
}

function New-SysColorsNotepadppStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.notepadpp
    if (-not $config) { return @() }

    $themePath = $config.themePath
    if (-not $themePath) {
        $themePath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Notepad++\themes\SysColors.xml'
    }
    $path    = Expand-SysColorsPath -Path $themePath
    $content = $config.content

    if (-not $content) { return @() }

    $apply = {
        param($step)
        $directory = Split-Path -Path $step.Path -Parent
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        Set-Content -LiteralPath $step.Path -Value $step.Metadata.Content -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'Notepad++ theme' -Target 'Notepad++' -Path $path -Metadata ([ordered]@{
        Content = $content
    }) -Apply $apply
}

function New-SysColorsVimStep {
    param(
        [psobject]$Theme
    )

    $config = $Theme.targets.vim
    if (-not $config) { return @() }

    $pathValue = $config.path
    if (-not $pathValue) { $pathValue = '~/.vimrc' }
    $path    = Expand-SysColorsPath -Path $pathValue

    $marker = $config.marker
    if (-not $marker) { $marker = '" SysColors start' }

    $endMark = $config.endMarker
    if (-not $endMark) { $endMark = '" SysColors end' }
    $block   = $config.block

    if (-not $block) { return @() }

    $apply = {
        param($step)
        $existing = ''
        if (Test-Path -LiteralPath $step.Path) {
            $existing = Get-Content -LiteralPath $step.Path -Raw
        }

        $pattern = [regex]::Escape($step.Metadata.Marker) + '.*?' + [regex]::Escape($step.Metadata.EndMarker)
        $replacement = "{0}`n{1}`n{2}" -f $step.Metadata.Marker, $step.Metadata.Block.TrimEnd(), $step.Metadata.EndMarker

        if ([string]::IsNullOrWhiteSpace($existing)) {
            $newContent = $replacement
        } elseif ($existing -match $pattern) {
            $newContent = [regex]::Replace($existing, $pattern, $replacement, 'Singleline')
        } else {
            $newContent = $existing.TrimEnd() + "`n`n" + $replacement
        }

        Set-Content -LiteralPath $step.Path -Value $newContent -Encoding UTF8
    }

    New-SysColorsPlanStep -Name 'Vim block' -Target 'Vim' -Path $path -Metadata ([ordered]@{
        Marker    = $marker
        EndMarker = $endMark
        Block     = $block
    }) -Apply $apply
}

function New-SysColorsPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject]$Theme
    )

    $steps = @()
    $steps += New-SysColorsWindowsTerminalStep -Theme $Theme
    $steps += New-SysColorsPowerShellProfileStep -Theme $Theme
    $steps += New-SysColorsBashStep -Theme $Theme
    $steps += New-SysColorsWindowsAccentStep -Theme $Theme
    $steps += New-SysColorsVSCodeStep -Theme $Theme
    $steps += New-SysColorsNotepadppStep -Theme $Theme
    $steps += New-SysColorsVimStep -Theme $Theme

    $steps | Where-Object { $_ }
}

function SysColors {
    [CmdletBinding(DefaultParameterSetName='ByName')]
    param(
        [Parameter(ParameterSetName='ByName', Position=0)] [string]$Name,
        [Parameter(ParameterSetName='ByPath', Mandatory)] [string]$Path,
        [Parameter(ParameterSetName='ByTheme', ValueFromPipeline, Mandatory)] [psobject]$Theme,
        [string[]]$Directory,
        [switch]$WhatIf,
        [switch]$SkipBackup
    )

    process {
        $theme = switch ($PSCmdlet.ParameterSetName) {
            'ByTheme' { $Theme }
            'ByPath'  { Import-SysColorsTheme -Path $Path }
            Default   { Import-SysColorsTheme -Name $Name -AdditionalDirectories $Directory }
        }

        if (-not $theme) { throw 'Failed to resolve the theme definition.' }

        $plan = New-SysColorsPlan -Theme $theme
        Invoke-SysColorsPlan -Plan $plan -WhatIf:$WhatIf -SkipBackup:$SkipBackup
    }
}

function SysColors-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)] [string]$Name,
        [string[]]$Directory,
        [switch]$WhatIf
    )

    $resolvedPath = Resolve-SysColorsThemePath -Name $Name -AdditionalDirectories $Directory

    if ($WhatIf) {
        return $resolvedPath
    }

    foreach ($commandName in @('code', 'code.cmd')) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $invocation = if ($command.Path) { $command.Path } else { $command.Name }

        & $invocation $resolvedPath
        return $resolvedPath
    }

    throw "Visual Studio Code command-line interface ('code' or 'code.cmd') was not found."
}

function SysColors-Restore {
    [CmdletBinding(DefaultParameterSetName='List')]
    param(
        [Parameter(ParameterSetName='Restore', Position=0)] [string]$Name,
        [Parameter(ParameterSetName='Restore')] [switch]$Latest,
        [Parameter(ParameterSetName='Restore')] [switch]$WhatIf,
        [switch]$List
    )

    $backups = Get-SysColorsBackups

    if ($List -or $PSCmdlet.ParameterSetName -eq 'List') {
        return $backups
    }

    $target = $null
    if ($Latest -or -not $Name) {
        $target = $backups | Sort-Object Timestamp -Descending | Select-Object -First 1
    } else {
        $target = $backups | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    }

    if (-not $target) {
        throw 'No matching backup was found.'
    }

    Restore-SysColorsBackupSet -Backup $target -WhatIf:$WhatIf
    return $target
}

function SysColor {
    [CmdletBinding()]
    param(
        [switch]$Back,
        [switch]$Themes,
        [switch]$Backups,
        [string]$Theme,
        [string]$Config,
        [string]$Path,
        [string[]]$Directory,
        [switch]$SkipBackup,
        [switch]$WhatIf
    )

    dynamicparam {
        $runtimeParameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

        try {
            $resolvedThemeNames = SysColors-List | Select-Object -ExpandProperty Name -ErrorAction Stop
        } catch {
            $resolvedThemeNames = @()
        }

        Set-Variable -Name 'SysColorDynamicThemeNames' -Value $resolvedThemeNames -Scope 1

        foreach ($themeName in ($resolvedThemeNames | Sort-Object -Unique)) {
            if (-not $themeName) { continue }

            $attribute = [System.Management.Automation.ParameterAttribute]::new()
            $attribute.HelpMessage = "Apply the '$themeName' theme."

            $collection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $collection.Add($attribute)

            $parameter = [System.Management.Automation.RuntimeDefinedParameter]::new($themeName, [switch], $collection)
            $runtimeParameters.Add($themeName, $parameter)
        }

        return $runtimeParameters
    }

    process {
        $requestedTheme = $Theme

        $dynamicThemeNamesVariable = Get-Variable -Name 'SysColorDynamicThemeNames' -ErrorAction SilentlyContinue
        if ($dynamicThemeNamesVariable) {
            $dynamicThemeNames = $dynamicThemeNamesVariable.Value
        } else {
            $dynamicThemeNames = @()
        }

        foreach ($themeName in $dynamicThemeNames) {
            if ($PSBoundParameters.ContainsKey($themeName) -and $PSBoundParameters[$themeName]) {
                if ($requestedTheme -and ($requestedTheme -ne $themeName)) {
                    throw "Multiple themes were requested ('$requestedTheme' and '$themeName'). Choose a single theme."
                }

                $requestedTheme = $themeName
            }
        }

        $selection = @()
        if ($Themes) { $selection += 'Themes' }
        if ($Backups) { $selection += 'Backups' }
        if ($Back) { $selection += 'Back' }
        if ($Path) { $selection += 'Path' }
        if ($Config) { $selection += 'Config' }
        if ($requestedTheme) { $selection += 'Theme' }

        if ($selection.Count -gt 1) {
            throw "Choose a single action. The parameters $($selection -join ', ') cannot be combined."
        }

        if ($Themes) {
            return SysColors-List -Directory $Directory
        }

        if ($Backups) {
            return SysColors-Restore -List
        }

        if ($Back) {
            return SysColors-Restore -Latest -WhatIf:$WhatIf
        }

        if ($Path) {
            return SysColors -Path $Path -WhatIf:$WhatIf -SkipBackup:$SkipBackup
        }

        if ($Config) {
            return SysColors-Config -Name $Config -Directory $Directory -WhatIf:$WhatIf
        }

        if ($requestedTheme) {
            return SysColors -Name $requestedTheme -Directory $Directory -WhatIf:$WhatIf -SkipBackup:$SkipBackup
        }

        throw 'Specify a theme switch (for example, -monokai), use -Config <Name> to edit a theme, -Path <File>, or choose an action switch such as -Themes, -Backups, or -Back.'
    }
}

Set-Alias -Name sc -Value SysColor

Export-ModuleMember -Function SysColors, SysColors-List, SysColors-Where, SysColors-Config, SysColors-Restore, SysColor -Alias sc
