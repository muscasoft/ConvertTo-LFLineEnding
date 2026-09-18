<#
.SYNOPSIS
    Normalizes line endings of PowerShell script files to LF.

.DESCRIPTION
    Recursively finds every .ps1 file under the given path and rewrites
    files that are encoded as UTF-8 with a byte order mark (BOM) so that
    they use LF line endings only. The BOM is preserved on write, since
    Windows PowerShell relies on it to detect UTF-8 correctly.

    Files that are not UTF-8 with BOM are left untouched and reported as
    skipped, since rewriting their encoding is out of scope for this script.

.PARAMETER Path
    Root folder to scan. Defaults to the current directory.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -WhatIf
    Preview which files would change, without writing anything.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = "."
)

function Test-Utf8Bom {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

$files = Get-ChildItem -Path $Path -Filter "*.ps1" -Recurse -File

$changed = 0
$unchanged = 0
$skipped = 0
$errored = 0

foreach ($file in $files) {
    try {
        if (-not (Test-Utf8Bom -FilePath $file.FullName)) {
            $skipped++
            continue
        }

        $original = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $normalized = $original -replace "`r`n|`r", "`n"

        if ($normalized -ne $original) {
            if ($PSCmdlet.ShouldProcess($file.FullName, "Normalize line endings to LF")) {
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($file.FullName, $normalized, $utf8Bom)
                Write-Output "Normalized: $($file.FullName)"
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
Write-Output "Done. $changed file(s) normalized, $unchanged already LF, $skipped skipped (not UTF-8 BOM), $errored error(s)."