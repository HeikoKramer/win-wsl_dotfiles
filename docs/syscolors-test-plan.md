# SysColors Test Plan

This document tracks the manual (or scripted) verification steps for the SysColors theme module.
Run the applicable command(s) after applying changes or when validating a new release. Update this
checklist whenever new targets or capabilities are added so that the coverage stays current.

## 1. Preparation

1. Launch PowerShell with the SysColors module available (the profile imports it automatically).
2. Ensure the desired theme exists by listing the catalog:

   ```powershell
   SysColors-List | Format-Table Name, Description, Targets
   ```

3. (Optional) Inspect the expanded theme metadata before running any commands:

   ```powershell
   SysColors-List -Detailed | Where-Object Name -eq '<ThemeName>' | Format-List
   ```

## 2. Theme application


**Apply a theme by name**

```powershell
SysColors '<ThemeName>'
```

**Apply a theme from a specific file path**

```powershell
SysColors -Path 'C:\path\to\theme.yml'
```

**Apply without taking a backup (for rapid iteration only)**

```powershell
SysColors '<ThemeName>' -SkipBackup
```

**Apply a theme by name**

```powershell
SysColors '<ThemeName>'
``` 

**Apply a theme from a specific file path**

```powershell
SysColors -Path 'C:\path\to\theme.yml'
``` 

**Apply without taking a backup (for rapid iteration only)**

```powershell
SysColors '<ThemeName>' -SkipBackup
``` 


After running an apply command, continue with the per-writer validation section.

## 3. Preview mode (`-WhatIf`)


**Review the execution plan without writing to disk**

```powershell
SysColors '<ThemeName>' -WhatIf -Verbose
```

**Preview when supplying an explicit file**

```powershell
SysColors -Path 'C:\path\to\theme.yml' -WhatIf -Verbose
```

**Review the execution plan without writing to disk**

```powershell
SysColors '<ThemeName>' -WhatIf -Verbose
``` 

**Preview when supplying an explicit file**

```powershell
SysColors -Path 'C:\path\to\theme.yml' -WhatIf -Verbose
``` |


Confirm that each step prints the expected destination path before executing the actual apply.

## 4. Restore workflow


**List available backups and their targets**

```powershell
SysColors-Restore -List | Format-Table Timestamp, Description, Path
```

**Restore the most recent snapshot**

```powershell
SysColors-Restore -Latest
```

**Restore a specific backup by name**

```powershell
SysColors-Restore '<BackupFolderName>'
```

**Dry-run a restore**

```powershell
SysColors-Restore -Latest -WhatIf
```

**List available backups and their targets**

```powershell
SysColors-Restore -List | Format-Table Timestamp, Description, Path
``` 

**Restore the most recent snapshot**

```powershell
SysColors-Restore -Latest
``` 

**Restore a specific backup by name**

```powershell
SysColors-Restore '<BackupFolderName>'
``` 

**Dry-run a restore**

```powershell
SysColors-Restore -Latest -WhatIf
``` 


After restoring, re-run the relevant per-writer checks to confirm the previous state returned.

## 5. Per-writer validation checklist

Execute these commands to confirm that each writer applied the requested settings. Replace `<ThemeName>`
or file paths as needed for the test scenario.

### 5.1 Windows Terminal settings

```powershell
$wtPath = [Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
$wtSettings = Get-Content $wtPath -Raw | ConvertFrom-Json -Depth 100
$wtSettings.schemes | Where-Object name -eq '<SchemeName>'
$wtSettings.profiles.defaults
```

Verify that the color scheme exists and that profile defaults reflect the applied theme. If the theme updates individual
profiles, query `$wtSettings.profiles.list` for the relevant profile name.

### 5.2 PowerShell profile block

```powershell
$profilePath = Join-Path (Split-Path $PROFILE -Parent) 'Microsoft.PowerShell_profile.ps1'
Get-Content $profilePath -Raw | Select-String -Pattern '#region SysColors' -Context 0,20
```

Ensure the rendered block sits between the SysColors markers and contains the expected content.

### 5.3 Bash profile block (run inside WSL)

```bash
sed -n '/# >>> SysColors >>>/,/# <<< SysColors <<</p' ~/.bashrc
```

Confirm the block matches the theme-provided snippet.

### 5.4 Windows registry accent color

```powershell
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'ColorizationColor' | Select-Object ColorizationColor
```

The returned ARGB value should reflect the theme's accent color.

### 5.5 Wallpaper path

```powershell
Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper | Select-Object Wallpaper
```

Confirm the wallpaper path matches the theme metadata and that the file exists.

### 5.6 Visual Studio Code

```powershell
$vscodeSettings = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Code\User\settings.json'
Get-Content $vscodeSettings -Raw | ConvertFrom-Json -Depth 100 | Select-Object 'workbench.colorTheme','workbench.colorCustomizations','editor.tokenColorCustomizations'
```

Check that the theme name and customization blocks align with the applied theme.

### 5.7 Notepad++

```powershell
$notepadTheme = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Notepad++\themes\SysColors.xml'
Test-Path $notepadTheme
Get-Content $notepadTheme -TotalCount 40
```

Verify the theme file exists and contains the expected XML.

### 5.8 Vim configuration (WSL or Windows Vim)

```bash
sed -n "/\" SysColors start\"/,/\" SysColors end\"/p" ~/.vimrc
```

Make sure the SysColors block is present and updated.

Keep this file synchronized with the module: add verification steps whenever a new writer or capability is introduced.
