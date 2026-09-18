# ConvertTo-LFLineEnding.ps1

Normalizes the line endings of PowerShell script files (`.ps1`) to LF (`\n`).

## Why

Windows PowerShell relies on a UTF-8 byte order mark (BOM) to correctly
detect UTF-8 encoding. This script only touches files that are already
UTF-8 with BOM, and preserves that BOM on write — it never changes a
file's encoding, only its line endings.

Files that are **not** UTF-8 with BOM (plain UTF-8, ANSI, UTF-16, etc.)
are left untouched and reported as skipped.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- Windows, macOS, or Linux

## Usage

```powershell
# Normalize every .ps1 file under the current directory
.\ConvertTo-LFLineEnding.ps1

# Normalize every .ps1 file under a specific path
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo

# Preview which files would change, without writing anything
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -WhatIf

# Also add a UTF-8 BOM to files that don't have one yet, then normalize
# their line endings to LF
.\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -AddBom
```

`-WhatIf` and `-Confirm` are supported natively via
`[CmdletBinding(SupportsShouldProcess)]`.

## Behavior

For every `.ps1` file found recursively under `-Path`:

1. **Content is not valid UTF-8** (e.g. Windows-1252/ANSI, UTF-16, or any
   encoding whose non-ASCII bytes don't decode as valid UTF-8): always
   skipped, even with `-AddBom` — adding a BOM doesn't fix the underlying
   encoding and would risk corrupting the file if written back. Its path
   is always printed (e.g. `Skipped (not valid UTF-8 - likely
   Windows-1252/ANSI or another encoding): C:\repo\foo.ps1`).
2. **Valid UTF-8 without a BOM**:
   - Without `-AddBom` → skipped, and its full path is always printed
     (e.g. `Skipped (valid UTF-8, but no BOM): C:\repo\foo.ps1`).
   - With `-AddBom` → a UTF-8 BOM is added and its line endings are
     normalized to LF in the same write.
3. **UTF-8 with BOM**:
   - All CRLF and lone CR line endings are converted to LF.
   - If nothing changed, the file is left as-is (counted as "already LF").
   - If something changed, the file is rewritten in place, still UTF-8
     with BOM, now with LF-only line endings.
4. Any error reading or writing a file (locked file, permissions, etc.)
   is caught, reported as a warning, and counted — the script continues
   with the remaining files instead of stopping.

At the end, a summary is printed:

```
Done. 3 file(s) changed (0 with BOM added), 12 already LF, 1 skipped (no BOM), 1 skipped (not valid UTF-8), 0 error(s).
```

If any UTF-8 files were skipped for lacking a BOM, a closing tip reminds
you to re-run with `-AddBom`. If any files were skipped for not being
valid UTF-8 at all, a separate note explains that `-AddBom` cannot fix
those and that you'll need to re-encode them to UTF-8 yourself first.

## Testing

A Pester test suite is included in `ConvertTo-LFLineEnding.Tests.ps1`.

```powershell
Install-Module Pester -Scope CurrentUser -Force  # if not already installed
Invoke-Pester -Path .\ConvertTo-LFLineEnding.Tests.ps1
```

## Notes

- Only `.ps1` files are processed. `.git`, binaries, and other file types
  are never touched because they're excluded by the `*.ps1` filter.
- Run this once from the repo root and commit the result, or wire it into
  a pre-commit hook / CI check.