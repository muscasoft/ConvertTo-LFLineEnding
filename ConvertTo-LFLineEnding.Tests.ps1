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

            & $ScriptPath -Path $TestRoot

            $content = [System.IO.File]::ReadAllText($file)
            $content | Should -Not -Match "`r"
            $content | Should -Match "`n"
        }

        It "Converts lone CR line endings to LF" {
            $file = Join-Path $TestRoot "cr.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`rWrite-Host 'b'`r"

            & $ScriptPath -Path $TestRoot

            $content = [System.IO.File]::ReadAllText($file)
            $content | Should -Not -Match "`r"
        }

        It "Leaves an already-LF file unchanged" {
            $file = Join-Path $TestRoot "lf.ps1"
            $original = "Write-Host 'a'`nWrite-Host 'b'`n"
            New-Utf8BomFile -Path $file -Content $original

            $before = Get-Item $file | Select-Object -ExpandProperty LastWriteTimeUtc
            Start-Sleep -Milliseconds 50
            & $ScriptPath -Path $TestRoot
            $after = Get-Item $file | Select-Object -ExpandProperty LastWriteTimeUtc

            $after | Should -Be $before
            [System.IO.File]::ReadAllText($file) | Should -Be $original
        }

        It "Preserves the UTF-8 BOM after rewriting" {
            $file = Join-Path $TestRoot "bom.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`r`n"

            & $ScriptPath -Path $TestRoot

            Test-HasBom -Path $file | Should -BeTrue
        }
    }

    Context "Non-UTF-8-with-BOM files" {

        It "Skips a UTF-8 file without a BOM and leaves it untouched" {
            $file = Join-Path $TestRoot "nobom.ps1"
            $original = "Write-Host 'a'`r`n"
            New-Utf8NoBomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot

            [System.IO.File]::ReadAllText($file) | Should -Be $original
            Test-HasBom -Path $file | Should -BeFalse
        }
    }

    Context "File type filtering" {

        It "Ignores non-.ps1 files even if they contain CRLF" {
            $file = Join-Path $TestRoot "notes.txt"
            $original = "some`r`ntext`r`n"
            New-Utf8BomFile -Path $file -Content $original

            & $ScriptPath -Path $TestRoot

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
    }

    Context "Recursion" {

        It "Finds and normalizes .ps1 files in subdirectories" {
            $subDir = Join-Path $TestRoot "sub\deeper"
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            $file = Join-Path $subDir "nested.ps1"
            New-Utf8BomFile -Path $file -Content "Write-Host 'a'`r`n"

            & $ScriptPath -Path $TestRoot

            [System.IO.File]::ReadAllText($file) | Should -Not -Match "`r"
        }
    }
}
