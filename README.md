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

## Troubleshooting

- **Bash helpers missing:** ensure chezmoi is installed and that
  `dot_bashrc` is the active profile. The profile will attempt to render the
  helper file on start-up and log an error if rendering fails.
- **PowerShell shortcuts missing:** run `chezmoi apply` from PowerShell to
  regenerate the profile, or use the `fresh` shortcut to reload it.

## Conventions

- Chat communication happens in German, but all code and comments remain in
  English.
- Prefer editing shared shortcuts in the YAML file so both shells stay in sync.
- Keep scripts idempotent: running `chezmoi apply` multiple times should be safe
  on both platforms.
