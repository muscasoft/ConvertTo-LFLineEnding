# Changelog

## [1.1.0] - 2026-09-18

### Added
- `-AddBom` switch: converts valid-UTF-8 files that don't yet have a BOM
  by adding one, normalizing their line endings to LF in the same write.
- Strict UTF-8 validation (`Test-ValidUtf8Bytes`) for files without a BOM.
  Files whose bytes don't decode as valid UTF-8 (e.g. Windows-1252/ANSI)
  are now detected and reported with a distinct message, and are never
  touched, not even with `-AddBom` — adding a BOM cannot fix an incorrect
  underlying encoding and risked corrupting such files.
- Skipped files now always have their full path printed to the console,
  split into two categories: missing a BOM (`skipped (no BOM)`) and not
  valid UTF-8 at all (`skipped (not valid UTF-8)`). Previously, skipped
  files were only counted, not named.
- Closing tips printed after a run: a suggestion to re-run with `-AddBom`
  when BOM-less UTF-8 files were skipped, and a separate note explaining
  that `-AddBom` cannot fix files that aren't valid UTF-8.
- Additional Pester tests covering `-AddBom`, strict UTF-8 validation
  (including a Windows-1252/ANSI fixture), and the new console messages.
- `.PARAMETER AddBom` and a matching `.EXAMPLE` added to the script's
  comment-based help; `README.md` updated to document the new behavior.

### Changed
- Summary line now also reports files with a BOM added, and splits the
  skip count into "no BOM" and "not valid UTF-8".

## [1.0.0] - 2026-09-18

Initial published release.

### Added
- `ConvertTo-LFLineEnding.ps1`: recursively normalizes CRLF/CR line
  endings to LF in `.ps1` files that are UTF-8 with a BOM, preserving the
  BOM on write.
- `[CmdletBinding(SupportsShouldProcess)]` with native `-WhatIf`/`-Confirm`
  support.
- Comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
- Per-file `try`/`catch` error handling with a warning and an error
  counter, so a single locked or inaccessible file doesn't abort the run.
- `README.md` and `ConvertTo-LFLineEnding.Tests.ps1` (Pester test suite).
