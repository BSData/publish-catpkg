#!/usr/bin/env pwsh

$cmd = {
    $core = Import-Module ./lib/GitHubActionsCore -PassThru -Scope Local -Force

    if (-not (Test-Path docs)) { mkdir docs | Out-Null }
    Write-Output "| Cmdlet | Synopsis |" > docs/README.md
    Write-Output "|-|-|"                >> docs/README.md
    $core.ExportedCommands.Values | ForEach-Object {
        Get-Help $_.Name | Select-Object @{
            Name       = "Row"
            Expression = {
                $n = $_.Name.Trim()
                $s = $_.Synopsis.Trim()
                "| [$($n)]($($n).md) | $($s) |"
            }
        }
    } | Select-Object -Expand Row  >> docs/README.md
    $core.ExportedCommands.Values | ForEach-Object {
        Get-Help -Full $_.Name | Select-Object @{
            Name       = "Row"
            Expression = {
                $n = $_.Name.Trim()
                "# $n"
                "``````"
                $_
                "``````"
            }
        } | Select-Object -Expand Row  > "docs/$($_.Name).md"
    }
}
pwsh -c $cmd -wd $PSScriptRoot