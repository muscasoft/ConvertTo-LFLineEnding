#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ConvertTo-LFLineEnding.ps1

.DESCRIPTION
    Run with:
        Invoke-Pester -Path .\ConvertTo-LFLineEnding.Tests.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot "ConvertTo-LFLineEnding.ps1"

    function New-Utf8BomFile {
        param([string]$Path, [string]$Content)
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
    }

    function New-Utf8NoBomFile {
        param([string]$Path, [string]$Content)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    }

    function New-Windows1252File {
        <#
            Writes raw bytes containing 0xE9 (the Windows-1252/ANSI encoding
            of 'e' with an acute accent). That byte on its own is not a
            valid UTF-8 sequence, which is exactly what the script's strict
            UTF-8 check needs to catch.
        #>
        param([string]$Path)
        $bytes = [byte[]](0x57, 0x72, 0x69, 0x74, 0x65, 0xE9, 0x0D, 0x0A) # "Write" + 0xE9 + CRLF
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        return $bytes
    }

    function Test-HasBom {
        param([string]$Path)
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }
}

Describe "ConvertTo-LFLineEnding" {

    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $TestRoot | Out-Null
    }

    Context "UTF-8 with BOM files" {

        It "Converts CRLF line endings to LF" {
            $file = Join-Path $TestRoot "crlf.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`r`nWrite-Host 'b'`r`n"

            & $ScriptPath -Path $TestRoot *>$null

            $content = [System.IO.File]::ReadAllText($file)
            $content | Should -Not -Match "`r"
            $content | Should -Match "`n"
        }

        It "Converts lone CR line endings to LF" {
            $file = Join-Path $TestRoot "cr.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`rWrite-Host 'b'`r"

            & $ScriptPath -Path $TestRoot *>$null

            $content = [System.IO.File]::ReadAllText($file)
            $content | Should -Not -Match "`r"
        }

        It "Leaves an already-LF file unchanged" {
            $file = Join-Path $TestRoot "lf.ps1"
            $original = "Write-Host 'a'`nWrite-Host 'b'`n"
            New-Utf8BomFile -Path $file -Content $original

            $before = Get-Item $file | Select-Object -ExpandProperty LastWriteTimeUtc
            Start-Sleep -Milliseconds 50
            & $ScriptPath -Path $TestRoot *>$null
            $after = Get-Item $file | Select-Object -ExpandProperty LastWriteTimeUtc

            $after | Should -Be $before
            [System.IO.File]::ReadAllText($file) | Should -Be $original
        }

        It "Preserves the UTF-8 BOM after rewriting" {
            $file = Join-Path $TestRoot "bom.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`r`n"

            & $ScriptPath -Path $TestRoot *>$null

            Test-HasBom -Path $file | Should -BeTrue
        }
    }

    Context "Valid UTF-8 files without a BOM" {

        It "Skips the file by default and leaves it untouched" {
            $file = Join-Path $TestRoot "nobom.ps1"
            $original = "Write-Host 'a'`r`n"
            New-Utf8NoBomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot *>$null

            [System.IO.File]::ReadAllText($file) | Should -Be $original
            Test-HasBom -Path $file | Should -BeFalse
        }

        It "Prints the skipped file's path" {
            $file = Join-Path $TestRoot "nobom.ps1"
            New-Utf8NoBomFile -Path $file -Content "Write-Host 'a'`r`n"

            $output = & $ScriptPath -Path $TestRoot *>&1 | Out-String -Width 4096

            $output | Should -Match "Skipped \(valid UTF-8, but no BOM\)"
            $output | Should -Match ([regex]::Escape($file))
        }

        It "Prints a tip to re-run with -AddBom" {
            $file = Join-Path $TestRoot "nobom.ps1"
            New-Utf8NoBomFile -Path $file -Content "Write-Host 'a'`r`n"

            $output = & $ScriptPath -Path $TestRoot *>&1 | Out-String -Width 4096

            $output | Should -Match "Tip: re-run with -AddBom"
        }

        It "-AddBom adds a BOM and normalizes line endings in one pass" {
            $file = Join-Path $TestRoot "addbom.ps1"
            New-Utf8NoBomFile -Path $file -Content "Write-Host 'a'`r`n"

            & $ScriptPath -Path $TestRoot -AddBom *>$null

            Test-HasBom -Path $file | Should -BeTrue
            [System.IO.File]::ReadAllText($file) | Should -Not -Match "`r"
        }

        It "-AddBom only adds a BOM when line endings are already LF" {
            $file = Join-Path $TestRoot "addbomlf.ps1"
            New-Utf8NoBomFile -Path $file -Content "Write-Host 'a'`n"

            & $ScriptPath -Path $TestRoot -AddBom *>$null

            Test-HasBom -Path $file | Should -BeTrue
            [System.IO.File]::ReadAllText($file) | Should -Be "Write-Host 'a'`n"
        }

        It "No longer skips the file once -AddBom is used" {
            $file = Join-Path $TestRoot "addbom.ps1"
            New-Utf8NoBomFile -Path $file -Content "Write-Host 'a'`r`n"

            $output = & $ScriptPath -Path $TestRoot -AddBom *>&1 | Out-String -Width 4096

            $output | Should -Not -Match "Skipped \(valid UTF-8, but no BOM\)"
            $output | Should -Match "BOM added"
        }
    }

    Context "Files that are not valid UTF-8 (e.g. Windows-1252/ANSI)" {

        It "Skips the file and leaves its bytes untouched" {
            $file = Join-Path $TestRoot "ansi.ps1"
            $originalBytes = New-Windows1252File -Path $file

            & $ScriptPath -Path $TestRoot *>$null

            [System.IO.File]::ReadAllBytes($file) | Should -Be $originalBytes
        }

        It "Is still skipped and left untouched even with -AddBom" {
            $file = Join-Path $TestRoot "ansi.ps1"
            $originalBytes = New-Windows1252File -Path $file

            & $ScriptPath -Path $TestRoot -AddBom *>$null

            [System.IO.File]::ReadAllBytes($file) | Should -Be $originalBytes
            Test-HasBom -Path $file | Should -BeFalse
        }

        It "Prints a distinct 'not valid UTF-8' message" {
            $file = Join-Path $TestRoot "ansi.ps1"
            New-Windows1252File -Path $file | Out-Null

            $output = & $ScriptPath -Path $TestRoot *>&1 | Out-String -Width 4096

            $output | Should -Match "not valid UTF-8"
            $output | Should -Match ([regex]::Escape($file))
        }

        It "Does not print the -AddBom tip for these files" {
            $file = Join-Path $TestRoot "ansi.ps1"
            New-Windows1252File -Path $file | Out-Null

            $output = & $ScriptPath -Path $TestRoot *>&1 | Out-String -Width 4096

            $output | Should -Not -Match "Tip: re-run with -AddBom"
        }
    }

    Context "File type filtering" {

        It "Ignores non-.ps1 files even if they contain CRLF" {
            $file = Join-Path $TestRoot "notes.txt"
            $original = "some`r`ntext`r`n"
            New-Utf8BomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot *>$null

            [System.IO.File]::ReadAllText($file) | Should -Be $original
        }
    }

    Context "-WhatIf support" {

        It "Does not modify files when -WhatIf is passed" {
            $file = Join-Path $TestRoot "whatif.ps1"
            $original = "Write-Host 'a'`r`n"
            New-Utf8BomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot -WhatIf *>$null

            [System.IO.File]::ReadAllText($file) | Should -Be $original
        }

        It "Does not add a BOM when -WhatIf and -AddBom are combined" {
            $file = Join-Path $TestRoot "whatifaddbom.ps1"
            $original = "Write-Host 'a'`r`n"
            New-Utf8NoBomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot -AddBom -WhatIf *>$null

            [System.IO.File]::ReadAllText($file) | Should -Be $original
            Test-HasBom -Path $file | Should -BeFalse
        }
    }

    Context "Recursion" {

        It "Finds and normalizes .ps1 files in subdirectories" {
            $subDir = Join-Path $TestRoot "sub\deeper"
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            $file = Join-Path $subDir "nested.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`r`n"

            & $ScriptPath -Path $TestRoot *>$null

            [System.IO.File]::ReadAllText($file) | Should -Not -Match "`r"
        }
    }
}
