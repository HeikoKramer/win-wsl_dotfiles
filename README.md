# Windows + WSL dotfiles

This repository contains the configuration I use to keep my Windows 11 PowerShell
profile and the Bash environment inside WSL2 in sync. The layout follows
[chezmoi](https://www.chezmoi.io/) conventions so the same source files can be
applied on both operating systems.

## Repository layout

| Path | Purpose |
| --- | --- |
| `dot_bashrc` | Bash profile applied in WSL. Detects the dotfiles directory, refreshes the checkout with `chezmoi update`, renders helper functions, and sources shared shortcuts. |
| `home/dot_bash_functions.tmpl` | chezmoi template that turns the shared shortcut definitions into Bash functions. |
| `readonly_Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl` | PowerShell profile template. chezmoi renders the final `Microsoft.PowerShell_profile.ps1` on Windows. |
| `common/shortcuts.yml` | Single source of truth for helper commands and directory shortcuts that are rendered for both shells. |
| `common/functions.yml` | Shared function definitions (for example, Git helpers) that are rendered alongside the shortcuts. |

Quick reference:

- Run `shortcuts` (optionally with a category such as `DIRS`) to list the generated helpers from the YAML files.
- Run `functions` to focus on the custom helpers from `common/functions.yml`.
- Directory shortcuts land you in the target folder and, on Linux, automatically show the contents with `ls -la`.

## Installation

1. Install chezmoi on both Windows (PowerShell) and WSL.
2. Clone this repository and set the `DOTFILES` environment variable to the
   checkout path (chezmoi does this automatically when you run `chezmoi init`).
3. Apply the dotfiles with `chezmoi apply` from either shell. This renders the
   PowerShell profile, Bash helper functions, and any other managed files.
4. Open a new terminal session. Bash regenerates `~/.bash_functions` on demand
   and automatically sources it, so the shortcut helpers are always available.
   Both shells display the current Git branch and commit so you can see which
   version of the dotfiles is active.

## Helper commands

Two generated helpers keep the shells in sync:

- `shortcuts [CATEGORY]` lists every shortcut defined in `common/shortcuts.yml` (plus any generated functions). Use it to confirm the name, category, and description before calling a helper.
- `functions [CATEGORY]` lists the custom helpers stored in `common/functions.yml`. This is useful when you only need the higher-level workflows (for example, the Git `allg` helper).

Both commands understand the same categories used in the YAML files, so filtering stays consistent on Windows and Linux.

## Adding new shortcuts or aliases

1. Edit `common/shortcuts.yml` for shortcuts or `common/functions.yml` for
   reusable helpers. Each shortcut supports a `win`, `linux`, or `both`
   command. Provide an English description and keep the category (`cat`)
   consistent with the existing entries.
2. Run `chezmoi apply` to regenerate the derived files. The PowerShell profile
   and Bash helper functions will be rebuilt using the updated shortcut or
   function data.
3. Open a new shell or run the `short` helper to review the rendered shortcuts.


## SysColors PowerShell module

The `SysColors` PowerShell module lives under `readonly_Documents/PowerShell/Modules/SysColors`.
It discovers YAML theme definitions, builds an execution plan, and applies the updates to
multiple targets (Windows Terminal, the PowerShell profile, the Bash profile, Windows accent
color, and editors such as VS Code, Notepad++, and Vim).

Usage overview:

1. Ensure the [`powershell-yaml`](https://www.powershellgallery.com/packages/powershell-yaml)
   module is installed: `Install-Module powershell-yaml`.
2. Import the module (the rendered PowerShell profile does this automatically):
   `Import-Module SysColors`.
3. List available themes with `SysColors-List` or filter with `SysColors-Where`.
4. Open a theme definition for editing with `SysColors-Config <THEME_NAME>` (this launches
   Visual Studio Code via `code` or `code.cmd`).
5. Apply a theme with `SysColors <THEME_NAME>` (use `-WhatIf` to review the plan first).
6. Restore the most recent backup with `SysColors-Restore -Latest` or list backups
   with `SysColors-Restore -List` before selecting a specific snapshot.

### Quick SysColor helper

The module also exports a compact `SysColor` helper (alias `sc`) that wraps the
main cmdlets:

- `SysColor -themes` lists available themes (same as `SysColors-List`).
- `SysColor -backups` shows the saved snapshots (same as `SysColors-Restore -List`).
- `SysColor -back` restores the most recent snapshot (same as `SysColors-Restore -Latest`).
- `SysColor -config <Theme>` opens the referenced theme YAML in Visual Studio Code.
- A direct switch such as `SysColor -monokai` applies a theme via `SysColors`.

Combine the helper with `-WhatIf` and `-SkipBackup` to forward the options to the
underlying cmdlets.

Theme files live beside the module in the `themes` folder. Create new themes by
following the schema shown in `example.yml`. Wallpaper entries are optional—leave
the `wallpaper.path` or `targets.windows.wallpaper` values empty (`''`) to skip
changing the desktop background when applying a theme.
