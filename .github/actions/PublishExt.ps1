#!/usr/bin/env pwsh

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Path,
    [Parameter()]
    [string]
    $StagingPath,
    [Parameter()]
    [object]
    $Repository,
    [Parameter()]
    [object]
    $Release,
    [Parameter()]
    [string]
    $Token
)

Import-Module $PSScriptRoot/../../lib/GitHubActionsCore
Import-Module $PSScriptRoot/../../src/BsdataCatpkg

$buildArgs = @{
    Path                  = $Path
    StagingPath           = $StagingPath
    Repository            = $Repository.full_name
    RepositoryDisplayName = $Repository.description ? $Repository.description : $Repository.name
    RepositoryUrl         = $Repository.html_url
    Release               = $Release
}
$publishArgs = @{
    UploadUrl = $Release.upload_url
    AssetsUrl = $Release.assets_url
    Token     = $Token
}
Build-BsdataReleaseAssets @buildArgs | Publish-GitHubReleaseAsset @publishArgs -Force

Write-Host "Done" -ForegroundColor Green
