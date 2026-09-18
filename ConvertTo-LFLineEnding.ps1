<#
.SYNOPSIS
    Normalizes line endings of PowerShell script files to LF.

.DESCRIPTION
    Recursively finds every .ps1 file under the given path and rewrites
    files that are encoded as UTF-8 with a byte order mark (BOM) so that
    they use LF line endings only. The BOM is preserved on write, since
    Windows PowerShell relies on it to detect UTF-8 correctly.

    Files without a BOM are validated as strict UTF-8 before being touched:
      - Valid UTF-8 without a BOM: skipped by default (name always printed),
        or converted (BOM added, line endings normalized) with -AddBom.
      - Not valid UTF-8 (e.g. Windows-1252/ANSI, UTF-16, or any encoding
        with non-ASCII bytes that don't decode as UTF-8): always skipped,
        even with -AddBom, because adding a BOM would not fix the
        underlying encoding and would risk corrupting the file's content.

.PARAMETER Path
    Root folder to scan. Defaults to the current directory.

.PARAMETER AddBom
    If specified, files without a BOM that ARE valid UTF-8 get a UTF-8 BOM
    added (and their line endings normalized to LF in the same write).
    Files that are not valid UTF-8 to begin with are never touched, since
    this script cannot safely re-encode them.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -WhatIf
    Preview which files would change, without writing anything.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -AddBom
    Also add a UTF-8 BOM to files that are valid UTF-8 but don't have one
    yet, then normalize their line endings to LF.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = ".",
    [switch]$AddBom
)

function Test-Utf8Bom {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Test-ValidUtf8Bytes {
    <#
        Strictly validates whether a byte sequence is well-formed UTF-8.
        This is what catches Windows-1252/ANSI files: their high-byte
        characters (e.g. e9 for 'e' with accent) are not valid UTF-8
        sequences on their own and will throw here.
    #>
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [void]$strictUtf8.GetString($Bytes)
        return $true
    } catch [System.Text.DecoderFallbackException] {
        return $false
    }
}

$files = Get-ChildItem -Path $Path -Filter "*.ps1" -Recurse -File

$changed = 0
$unchanged = 0
$skippedNoBom = 0
$skippedNotUtf8 = 0
$bomAdded = 0
$errored = 0
$skippedNoBomFiles = @()

foreach ($file in $files) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $contentBytes = if ($hasBom) { $bytes[3..($bytes.Length - 1)] } else { $bytes }

        if (-not (Test-ValidUtf8Bytes -Bytes $contentBytes)) {
            # Not valid UTF-8 at all (e.g. Windows-1252/ANSI). Never touched,
            # -AddBom included, since we cannot safely re-encode it here.
            $skippedNotUtf8++
            Write-Output "Skipped (not valid UTF-8 - likely Windows-1252/ANSI or another encoding): $($file.FullName)"
            continue
        }

        if (-not $hasBom -and -not $AddBom) {
            $skippedNoBom++
            $skippedNoBomFiles += $file.FullName
            Write-Output "Skipped (valid UTF-8, but no BOM): $($file.FullName)"
            continue
        }

        $original = [System.Text.Encoding]::UTF8.GetString($contentBytes)
        $normalized = $original -replace "`r`n|`r", "`n"

        $needsBom = -not $hasBom -and $AddBom
        $lineEndingsChanged = ($normalized -ne $original)

        if ($needsBom -or $lineEndingsChanged) {
            $action = if ($needsBom -and $lineEndingsChanged) {
                "Add UTF-8 BOM and normalize line endings to LF"
            } elseif ($needsBom) {
                "Add UTF-8 BOM"
            } else {
                "Normalize line endings to LF"
            }

            if ($PSCmdlet.ShouldProcess($file.FullName, $action)) {
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($file.FullName, $normalized, $utf8Bom)

                $message = if ($needsBom -and $lineEndingsChanged) {
                    "BOM added and normalized"
                } elseif ($needsBom) {
                    "BOM added"
                } else {
                    "Normalized"
                }
                Write-Output "${message}: $($file.FullName)"
            }

            if ($needsBom) {
                $bomAdded++
            }
            $changed++
        } else {
            $unchanged++
        }
    }
    catch {
        $errored++
        Write-Warning "Failed to process $($file.FullName): $_"
    }
}

Write-Output ""
Write-Output "Done. $changed file(s) changed ($bomAdded with BOM added), $unchanged already LF, $skippedNoBom skipped (no BOM), $skippedNotUtf8 skipped (not valid UTF-8), $errored error(s)."

if ($skippedNoBomFiles.Count -gt 0) {
    Write-Output ""
    Write-Output "Tip: re-run with -AddBom to add a UTF-8 BOM to the skipped file(s) above and normalize them too."
}

if ($skippedNotUtf8 -gt 0) {
    Write-Output ""
    Write-Output "Note: $skippedNotUtf8 file(s) were skipped because they are not valid UTF-8 (see 'not valid UTF-8' lines above). -AddBom will not touch these; re-encode them to UTF-8 first (e.g. in your editor) before running this script again."
}
