# ConvertTo-LFLineEnding.ps1

Normalizes the line endings of Go (`.go`) or PowerShell (`.ps1`) source
files, and can fix their byte order mark (BOM) to match the encoding
convention expected for that file type.

## Why

- **ps1**: Windows PowerShell relies on a UTF-8 BOM to correctly detect
  UTF-8 encoding. PS1 files are therefore expected to be **UTF-8 with
  BOM**.
- **Go**: `gofmt`/`goimports` and the wider Go ecosystem expect
  **UTF-8 without a BOM**. A BOM on a `.go` file is a deviation from that
  convention.

This script only touches files that are already UTF-8 (with or without a
BOM, as appropriate) — it never guesses at or changes a file's underlying
character encoding, only its BOM and its line endings.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- Windows, macOS, or Linux

## Usage

```powershell
# Normalize every .ps1 file under the current directory to LF (default)
.\ConvertTo-LFLineEnding.ps1

# Normalize every .ps1 file under a specific path
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo

# Preview which files would change, without writing anything
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -WhatIf

# Also add a UTF-8 BOM to PS1 files that don't have one yet, then
# normalize their line endings
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -AddBom

# Normalize Go files instead of PS1 files
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -Type Go

# Normalize Go files and strip a UTF-8 BOM from any that have one
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -Type Go -RemoveBom

# Normalize PS1 files to CRLF instead of the default LF
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -LineEnding CRLF
```

`-WhatIf` and `-Confirm` are supported natively via
`[CmdletBinding(SupportsShouldProcess)]`.

## Parameters

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-Path` | any path | `.` | Root folder to scan recursively. |
| `-Type` | `ps1`, `Go` | `ps1` | Which file type to process and which BOM convention to enforce. |
| `-LineEnding` | `LF`, `CRLF` | `LF` | Target line ending. All CRLF/CR/LF variants found are normalized to this value. |
| `-AddBom` | switch | off | Adds a BOM to valid-UTF-8 ps1 files that don't have one. |
| `-RemoveBom` | switch | off | Strips the BOM from valid-UTF-8 Go files that have one. |
| `-IgnoreWarnings` | switch | off | Proceeds anyway past the warning-and-stop checks below. |

## Behavior

For every file of the selected `-Type` found recursively under `-Path`:

1. **Content is not valid UTF-8** (e.g. Windows-1252/ANSI, UTF-16, or any
   encoding whose non-ASCII bytes don't decode as valid UTF-8): always
   skipped, regardless of `-AddBom`/`-RemoveBom` — fixing the BOM can't
   repair an incorrect underlying encoding and would risk corrupting the
   file if written back. Its path is always printed (e.g. `Skipped (not
   valid UTF-8 - likely Windows-1252/ANSI or another encoding):
   C:\repo\foo.ps1`).
2. **Valid UTF-8, but the BOM doesn't match the type's convention**
   (a PS1 file missing a BOM, or a Go file that has one):
   - Without the matching fix switch → skipped, and its full path is
     always printed (e.g. `Skipped (valid UTF-8, but no BOM): ...` or
     `Skipped (valid UTF-8, but has a BOM): ...`).
   - With `-AddBom` (ps1) or `-RemoveBom` (Go) → the BOM is fixed and
     line endings are normalized in the same write.
3. **Valid UTF-8, BOM already matches the type's convention**:
   - All CRLF/CR/LF line endings are converted to `-LineEnding`.
   - If nothing changed, the file is left as-is (counted as "already
     LF"/"already CRLF").
   - If something changed, the file is rewritten in place, BOM
     unchanged, with the target line ending only.
4. Any error reading or writing a file (locked file, permissions, etc.)
   is caught, reported as a warning, and counted — the script continues
   with the remaining files instead of stopping.

At the end, a summary is printed:

```
Done. 3 file(s) changed (0 with BOM fixed), 12 already LF, 1 skipped (wrong BOM), 1 skipped (not valid UTF-8), 0 error(s).
```

If any files were skipped for a BOM mismatch, a closing tip reminds you
to re-run with `-AddBom` or `-RemoveBom` (whichever applies to the
current `-Type`). If any files were skipped for not being valid UTF-8 at
all, a separate note explains that neither switch can fix those and that
you'll need to re-encode them to UTF-8 yourself first.

## Warning-and-stop checks

Some parameter combinations go against the selected type's convention.
By default the script prints a warning and stops **before touching any
files**. Pass `-IgnoreWarnings` to proceed anyway.

| Combination | Why it warns |
|---|---|
| `-Type Go` + `-LineEnding CRLF` | Go's convention (via `gofmt`/`goimports`) is LF. |
| `-Type Go` + `-AddBom` | Go files are expected to be UTF-8 **without** a BOM. |
| `-Type PS1` + `-RemoveBom` | PS1 files are expected to be UTF-8 **with** a BOM. |

`-AddBom` and `-RemoveBom` cannot be combined with each other at all —
that always throws an error, `-IgnoreWarnings` included, since it's a
contradictory instruction rather than a risky-but-valid one.

## Testing

A Pester test suite is included in `ConvertTo-LFLineEnding.Tests.ps1`.

```powershell
Install-Module Pester -Scope CurrentUser -Force  # if not already installed
Invoke-Pester -Path .\ConvertTo-LFLineEnding.Tests.ps1
```

## Notes

- Only files matching the selected `-Type` are processed. `.git`,
  binaries, and other file types are never touched because they're
  excluded by the file filter (`*.ps1` or `*.go`).
- Run this once from the repo root and commit the result, or wire it into
  a pre-commit hook / CI check.