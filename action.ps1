#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

Import-Module $PSScriptRoot/lib/GitHubActionsCore
Import-Module $PSScriptRoot/src/BsdataCatpkg

# read inputs, set output
$uploadUrl = Get-ActionInput 'upload-url'
$token = Get-ActionInput 'token' -Required
$stagingPath = Get-ActionInput staging-path -Required
Set-ActionOutput staging-path $stagingPath

$event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$repo = $event.repository
$release = $event.release

$buildArgs = @{
    Path                  = '.'
    StagingPath           = $stagingPath
    Repository            = $repo.full_name
    RepositoryDisplayName = $repo.description ? $repo.description : $repo.name
    RepositoryUrl         = $repo.html_url
    Release               = $release
}
$publishArgs = @{
    UploadUrl = $uploadUrl ?? $release.upload_url
    AssetsUrl = $release.assets_url
    Token     = $token
}
Build-BsdataReleaseAssets @buildArgs | Publish-GitHubReleaseAsset @publishArgs -Force

Write-Host "Done" -ForegroundColor Green
