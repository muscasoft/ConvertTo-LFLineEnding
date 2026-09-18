<#
.SYNOPSIS
    Normalizes line endings of Go or PowerShell source files, and can fix
    their BOM to match the encoding convention for that file type.

.DESCRIPTION
    Recursively finds every file of the selected -Type under the given
    path and rewrites files that already match that type's expected
    UTF-8/BOM convention so their line endings match -LineEnding.

    Expected convention per -Type:
      - PS1: UTF-8 WITH a byte order mark (BOM). Windows PowerShell
             relies on the BOM to detect UTF-8 correctly.
      - Go:  UTF-8 WITHOUT a BOM. This is the convention enforced by
             gofmt/goimports; a BOM on a Go file is treated as a
             deviation from that convention.

    Files without a BOM are always validated as strict UTF-8 first:
      - Valid UTF-8: handled per the rules below.
      - Not valid UTF-8 (e.g. Windows-1252/ANSI, UTF-16, or any encoding
        with non-ASCII bytes that don't decode as UTF-8): always skipped,
        regardless of -AddBom/-RemoveBom, because fixing the BOM cannot
        repair an incorrect underlying encoding and risks corrupting the
        file's content.

    Files whose BOM doesn't match their type's convention:
      - PS1 file missing a BOM: skipped by default (path always printed),
        or fixed with -AddBom (BOM added, line endings normalized).
      - Go file that has a BOM: skipped by default (path always printed),
        or fixed with -RemoveBom (BOM stripped, line endings normalized).

.PARAMETER Path
    Root folder to scan. Defaults to the current directory.

.PARAMETER Type
    The kind of source file to process: 'PS1' or 'Go'. Defaults to 'PS1'.
    Determines both the file filter (*.ps1 / *.go) and the BOM convention
    that is checked and enforced (see .DESCRIPTION).

.PARAMETER LineEnding
    The target line ending: 'LF' (default) or 'CRLF'. All CRLF/CR/LF line
    endings found in a processed file are normalized to this value.

    Combining -Type Go with -LineEnding CRLF triggers a warning and stops
    the script, since Go's convention is LF, unless -IgnoreWarnings is
    specified.

.PARAMETER AddBom
    If specified, PS1 files without a BOM that ARE valid UTF-8 get a BOM
    added (and their line endings normalized in the same write). Files
    that are not valid UTF-8 to begin with are never touched. Using
    -AddBom together with -Type Go triggers a warning and stops the
    script (a BOM added to a Go file goes against its convention),
    unless -IgnoreWarnings is specified.

.PARAMETER RemoveBom
    If specified, Go files that have a BOM get it stripped (and their
    line endings normalized in the same write). Using -RemoveBom together
    with -Type PS1 triggers a warning and stops the script (PS1 files are
    expected to keep their BOM), unless -IgnoreWarnings is specified.
    Cannot be combined with -AddBom.

.PARAMETER IgnoreWarnings
    Suppresses the warning-and-stop behavior for combinations that go
    against a type's convention (-Type Go with -LineEnding CRLF, -Type Go
    with -AddBom, -Type PS1 with -RemoveBom) and proceeds anyway.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -WhatIf
    Preview which files would change, without writing anything.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -AddBom
    Also add a UTF-8 BOM to PS1 files that are valid UTF-8 but don't have
    one yet, then normalize their line endings to LF.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -Type Go -RemoveBom
    Normalize Go files to LF, and strip a UTF-8 BOM from any that have one.

.EXAMPLE
    .\ConvertTo-LFLineEnding.ps1 -Path C:\path\to\repo -Type PS1 -LineEnding CRLF
    Normalize PS1 files to CRLF instead of the default LF.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = ".",

    [ValidateSet('Go', 'PS1')]
    [string]$Type = 'PS1',

    [ValidateSet('LF', 'CRLF')]
    [string]$LineEnding = 'LF',

    [switch]$AddBom,
    [switch]$RemoveBom,
    [switch]$IgnoreWarnings
)

# --- Validate parameter combinations before touching any files ---------

if ($AddBom -and $RemoveBom) {
    throw "Cannot specify both -AddBom and -RemoveBom at the same time."
}

if ($Type -eq 'Go' -and $LineEnding -eq 'CRLF' -and -not $IgnoreWarnings) {
    Write-Warning "Type 'Go' with -LineEnding CRLF goes against Go's LF convention (enforced by gofmt/goimports). Stopping. Re-run with -IgnoreWarnings to proceed anyway."
    return
}

if ($Type -eq 'Go' -and $AddBom -and -not $IgnoreWarnings) {
    Write-Warning "-AddBom adds a BOM, but Go files are expected to be UTF-8 WITHOUT a BOM. Stopping. Re-run with -IgnoreWarnings to proceed anyway."
    return
}

if ($Type -eq 'PS1' -and $RemoveBom -and -not $IgnoreWarnings) {
    Write-Warning "-RemoveBom strips the BOM, but PS1 files are expected to be UTF-8 WITH a BOM. Stopping. Re-run with -IgnoreWarnings to proceed anyway."
    return
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

$filter = if ($Type -eq 'Go') { '*.go' } else { '*.ps1' }
$expectedHasBom = ($Type -eq 'PS1')
$targetLineEndingChars = if ($LineEnding -eq 'CRLF') { "`r`n" } else { "`n" }

$files = Get-ChildItem -Path $Path -Filter $filter -Recurse -File

$changed = 0
$unchanged = 0
$skippedWrongBom = 0
$skippedNotUtf8 = 0
$bomFixed = 0
$errored = 0
$skippedWrongBomFiles = @()

foreach ($file in $files) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $contentBytes = if ($hasBom) { $bytes[3..($bytes.Length - 1)] } else { $bytes }

        if (-not (Test-ValidUtf8Bytes -Bytes $contentBytes)) {
            # Not valid UTF-8 at all (e.g. Windows-1252/ANSI). Never touched,
            # regardless of -AddBom/-RemoveBom, since we cannot safely
            # re-encode it here.
            $skippedNotUtf8++
            Write-Output "Skipped (not valid UTF-8 - likely Windows-1252/ANSI or another encoding): $($file.FullName)"
            continue
        }

        $bomMatchesConvention = ($hasBom -eq $expectedHasBom)
        $canFixBom = if ($expectedHasBom) { $AddBom } else { $RemoveBom }

        if (-not $bomMatchesConvention -and -not $canFixBom) {
            $skippedWrongBom++
            $skippedWrongBomFiles += $file.FullName
            $reason = if ($expectedHasBom) { "valid UTF-8, but no BOM" } else { "valid UTF-8, but has a BOM" }
            Write-Output "Skipped ($reason): $($file.FullName)"
            continue
        }

        $original = [System.Text.Encoding]::UTF8.GetString($contentBytes)
        $normalized = $original -replace "`r`n|`r|`n", $targetLineEndingChars

        $needsBomFix = -not $bomMatchesConvention -and $canFixBom
        $lineEndingsChanged = ($normalized -ne $original)

        if ($needsBomFix -or $lineEndingsChanged) {
            $bomFixVerb = if ($expectedHasBom) { "Add UTF-8 BOM" } else { "Remove UTF-8 BOM" }
            $action = if ($needsBomFix -and $lineEndingsChanged) {
                "$bomFixVerb and normalize line endings to $LineEnding"
            } elseif ($needsBomFix) {
                $bomFixVerb
            } else {
                "Normalize line endings to $LineEnding"
            }

            if ($PSCmdlet.ShouldProcess($file.FullName, $action)) {
                $outputBom = New-Object System.Text.UTF8Encoding($expectedHasBom)
                [System.IO.File]::WriteAllText($file.FullName, $normalized, $outputBom)

                $bomFixMessage = if ($expectedHasBom) { "BOM added" } else { "BOM removed" }
                $message = if ($needsBomFix -and $lineEndingsChanged) {
                    "$bomFixMessage and normalized"
                } elseif ($needsBomFix) {
                    $bomFixMessage
                } else {
                    "Normalized"
                }
                Write-Output "${message}: $($file.FullName)"
            }

            if ($needsBomFix) {
                $bomFixed++
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
Write-Output "Done. $changed file(s) changed ($bomFixed with BOM fixed), $unchanged already $LineEnding, $skippedWrongBom skipped (wrong BOM), $skippedNotUtf8 skipped (not valid UTF-8), $errored error(s)."

if ($skippedWrongBomFiles.Count -gt 0) {
    Write-Output ""
    if ($expectedHasBom) {
        Write-Output "Tip: re-run with -AddBom to add a UTF-8 BOM to the skipped file(s) above and normalize them too."
    } else {
        Write-Output "Tip: re-run with -RemoveBom to strip the UTF-8 BOM from the skipped file(s) above and normalize them too."
    }
}

if ($skippedNotUtf8 -gt 0) {
    Write-Output ""
    Write-Output "Note: $skippedNotUtf8 file(s) were skipped because they are not valid UTF-8 (see 'not valid UTF-8' lines above). -AddBom/-RemoveBom will not touch these; re-encode them to UTF-8 first (e.g. in your editor) before running this script again."
}
