#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

# check if there are any cat/gst files to process, otherwise short-circuit out
if ((Get-ChildItem -Recurse -Include *.cat, *.gst -File).Length -eq 0) {
    Write-Host "No datafiles to process and publish." -ForegroundColor Green
    exit 0
}

Import-Module $PSScriptRoot/lib/GitHubActionsCore

# install wham if necessary
$wham = "$PSScriptRoot/lib/wham"
if ($null -eq (Get-Command $wham -ErrorAction SilentlyContinue)) {
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 1
    dotnet tool install wham --version 0.7.0 --tool-path "$PSScriptRoot/lib"
}

# read inputs, set output
$stagingPath = Get-ActionInput staging-path -Required
Set-ActionOutput staging-path $stagingPath
$repo = ($env:GITHUB_REPOSITORY -split '/')[1]
$event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$tag = $event.release.tag_name
$repoName = $event.repository.description, $event.repository.name | Select-Object -First 1
$repoBaseUrl = $event.repository.html_url

# this method builds an URL to various github locations
function Get-GitHubUrl {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,
        [Parameter(ParameterSetName = 'tag', Position = 1, Mandatory)]
        [string] $ReleaseTag,
        [Parameter(ParameterSetName = 'latest', Mandatory)]
        [switch] $LatestReleaseAsset,
        [Parameter(ParameterSetName = 'blob', Position = 1, Mandatory)]
        [switch] $Blob,
        [Parameter(ParameterSetName = 'blob', Position = 2, Mandatory)]
        [string] $Commitish,
        [Parameter()]
        [string] $RepositoryBaseUrl = $repoBaseUrl
    )
    $escapedName = [uri]::EscapeDataString($Name)
    $middleSegment = if ($Blob) {
        "blob/$Commitish"
    }
    elseif ($LatestReleaseAsset) {
        'releases/latest/download'
    }
    else {
        $escapedTag = [uri]::EscapeDataString($ReleaseTag)
        "releases/download/$escapedTag"
    }
    return "$RepositoryBaseUrl/$middleSegment/$escapedName"
}

# this function returns an escaped name that will be accepted as github release asset name
function Get-EscapedAssetName {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )
    # according to https://developer.github.com/v3/repos/releases/#upload-a-release-asset
    # GitHub renames asset filenames that have special characters, non-alphanumeric characters, and leading or trailing periods.
    # Let's do that ourselves first so we know exact filename before upload.
    # 1. replace any group of non a-z, digit, hyphen or underscore chars with a single period
    $periodsOnly = $Name -creplace '[^a-zA-Z\d\-_]+', '.'
    # 2. remove any leading or trailing period
    return $periodsOnly.Trim('.')
}

# create catz/gstz files
& $wham publish -a zip -o $stagingPath

# rename files so that they have release asset-compatible names, save mappings
$datafiles = Get-ChildItem $stagingPath -Recurse -Include *.catz, *.gstz -File | ForEach-Object {
    # drop 'z' from extension
    $OriginalName = $_.Name.Remove($_.Name.Length - 1)
    $File = $_ | Rename-Item -NewName (Get-EscapedAssetName $_.Name) -PassThru
    return @{
        originalName = $OriginalName
        file         = $File
        sha256       = (Get-FileHash $File 'SHA256').Hash
    }
}
$datafiles | ForEach-Object { Write-Host "Staged '$($_.originalName)' as '$($_.file.Name)'" -ForegroundColor Green }

# publish indexes based on catz/gstz datafiles (already renamed)
Push-Location $stagingPath
# 'tag' assets: create '$repo.$tag.bsi' and '$repo.$tag.bsr'
& $wham publish -a bsr bsi -f "$repo.$tag" --repo-name $repoName --url $(Get-GitHubUrl "$repo.$tag.bsi" $tag)

# 'latest' assets: create '$repo.latest.bsi'
& $wham publish -a bsi -f "$repo.latest" --repo-name $repoName --url $(Get-GitHubUrl "$repo.latest.bsi" -LatestReleaseAsset)
Pop-Location

$bugTrackerUrl = $repoBaseUrl + '/issues'
$reportBugUrl = 'http://battlescribedata.appspot.com/#/repo/' + $repo
$catpkgJsonFilename = "$repo.catpkg.json"

# build '$repo.catpkg.json' content
$bsdatajson = [ordered]@{
    '$schema'             = 'https://raw.githubusercontent.com/BSData/schemas/master/src/catpkg.schema.json'
    name                  = $repo
    description           = $repoName
    battleScribeVersion   = $null # set below
    version               = $tag
    lastUpdated           = ($event.release.published_at, $event.release.created_at | Select-Object -First 1)[0]
    lastUpdateDescription = $event.release.name
    indexUrl              = Get-GitHubUrl "$repo.latest.bsi" -LatestReleaseAsset
    repositoryUrl         = Get-GitHubUrl $catpkgJsonFilename -LatestReleaseAsset
    githubUrl             = $event.repository.html_url
    feedUrl               = $repoBaseUrl + '/releases.atom'
    bugTrackerUrl         = $bugTrackerUrl
    reportBugUrl          = $reportBugUrl
    repositoryFiles       = @($datafiles | ForEach-Object {
            # considered reading index.bsi, but loading zip to memory in powershell
            # required using .net types and was messy
            # also it's expected wham will take over creation of catpkg json in future
            $nonzipFilename = $_.originalName
            $xml = if (Test-Path $nonzipFilename) { [xml](Get-Content $nonzipFilename) }
            if ($null -eq $xml) {
                throw "Cannot index '$($_.file.Name)' - didn't find '$nonzipFilename'."
            }
            $root = $xml.catalogue, $xml.gameSystem | Select-Object -First 1
            return [ordered]@{
                id                  = $root.id
                name                = $root.name
                type                = $root.LocalName.ToLowerInvariant()
                revision            = [int]$root.revision
                battleScribeVersion = $root.battleScribeVersion
                fileUrl             = Get-GitHubUrl $_.file.Name -LatestReleaseAsset
                githubUrl           = Get-GitHubUrl $nonzipFilename -Blob $event.release.target_commitish
                bugTrackerUrl       = $bugTrackerUrl
                reportBugUrl        = $reportBugUrl
                authorName          = $root.authorName
                authorContact       = $root.authorContact
                authorUrl           = $root.authorUrl
                sha256              = $_.sha256
            }
        })
}
# select "highest" version via lexicographical (alphanumeric) order
$bsdatajson.battleScribeVersion = $bsdatajson.repositoryFiles.battleScribeVersion | Sort-Object -Bottom 1

# save json to file
$bsdatajson | ConvertTo-Json -Compress | Set-Content (Join-Path $stagingPath $catpkgJsonFilename)

# this function performs uri template expansion (only query part)
function Expand-UriTemplate {
    param (
        [Parameter(Mandatory)]
        [string] $template,
        [Parameter()]
        [hashtable] $values = @{ }
    )
    # expands only query part template, based on https://github.com/octokit/octokit.net/blob/74dc51a6f567395d0c46d97f7270f959d671573e/Octokit/Helpers/StringExtensions.cs#L46-L68
    $regex = [regex]::new('\{\?([^}]+)\}')
    $match = $regex.Match($template)
    if ($match.Success) {
        $expansion = ''
        $query = $match.Groups[1].Value.Split(',') | ForEach-Object {
            $key = $_
            $value = $values.$key
            if ([string]::IsNullOrWhiteSpace($value)) {
                return $null
            }
            $escapedValue = [uri]::EscapeDataString($value)
            return "$key=$escapedValue"
        } | Where-Object { $null -ne $_ } | Join-String -Separator '&'
        if (-not [string]::IsNullOrWhiteSpace($query)) {
            $expansion += "?$query"
        }
        return $regex.Replace($template, $expansion)
    }
    return $template
}

# prepare upload info

$uploadUrl = Get-ActionInput 'upload-url' -Required
$token = Get-ActionInput 'token' -Required
$authHeaders = @{
    Headers = @{
        Authorization = "token $token"
    }
}
# get previous assets
$previousAssets = Invoke-RestMethod $event.release.assets_url @authHeaders -FollowRelLink | ForEach-Object { $_ }

# staged assets prepared for upload
$stagedAssets = Get-ChildItem $stagingPath -Include *.json, *.bsi, *.bsr, *.gstz, *.catz -Recurse -File | Sort-Object -Property Name

# checksums: calculate, compare to uploaded if exists, stage if not or differs
$checksums = [ordered]@{
    git_sha = $env:GITHUB_SHA
    files     = [ordered]@{ }
}
$stagedAssets | ForEach-Object {
    $checksums.files[$_.Name] = (Get-FileHash $_).Hash
}
$checksumFilename = 'checksums.json'
$checksumFilepath = Join-Path $stagingPath $checksumFilename
$existingChecksumAsset = $previousAssets | Where-Object name -eq $checksumFilename
if ($existingChecksumAsset) {
    # check previous checksums
    Write-Host "Downloading existing $checksumFilename for comparison."
    $apiArgs = @{
        Method  = 'Get'
        Uri     = $existingChecksumAsset.url
        OutFile = $checksumFilepath
        Headers = @{
            Accept = 'application/octet-stream'
        } + $authHeaders.Headers
    }
    $null = Invoke-RestMethod @apiArgs -MaximumRetryCount 5 -RetryIntervalSec 5
    $existingChecksums = Get-Content $checksumFilepath | ConvertFrom-Json
    $same = $checksums.git_sha -eq $existingChecksums.git_sha -and ($stagedAssets | Where-Object {
            $savedSha = $existingChecksums.files[$_.Name]
            $equal = $null -ne $savedSha -and $savedSha -eq $checksums.files[$_.Name]
            if (!$equal) {
                Write-Host "Checksum differs for '$($_.Name)'."
            }
        } | Select-Object -First 1)
    if ($same) {
        Write-Host "Checksums are the same. Skipping re-upload."
        exit 0
    }
    Write-Host "Checksums differ."
}
else {
    Write-Host "$checksumFilename isn't an existing asset."
}
Write-Host "Adding $checksumFilename to staged assets."
$checksums | ConvertTo-Json -Compress | Set-Content $checksumFilepath
$checksumFile = Get-Item $checksumFilepath
$stagedAssets = @() + $checksumFile + $stagedAssets

# upload assets (delete old ones with the same name first)
$stagedAssets | ForEach-Object {
    $name = $_.Name
    $path = $_.FullName
    $mime = if ($_.Extension -ne '.json') { 'application/zip' } else { 'application/json' }
    $duplicate = $previousAssets | Where-Object name -eq $name | Select-Object -First 1
    if ($duplicate) {
        # delete duplicate first
        Write-Host "Deleting $name" -ForegroundColor Gray
        Invoke-RestMethod $duplicate.url -Method Delete @authHeaders | Out-Null
    }
    $apiArgs = @{
        Method      = 'Post'
        Uri         = Expand-UriTemplate $uploadUrl @{ name = $name }
        InFile      = $path
        ContentType = $mime
    }
    Write-Host "Uploading $name to $($apiArgs.Uri)"
    $attempt = 0
    do {
        $attempt++
        $done = $attempt -ge 5
        try {
            $res = Invoke-RestMethod @apiArgs @authHeaders
            $done = $true
        }
        catch {
            if ($done) {
                Write-Verbose "    Attempt $attempt failed."
                throw
            }
            else {
                $delay = 5 * $attempt
                Write-Verbose "    Attempt $attempt failed. Retrying in $delay seconds..."
                Start-Sleep $delay
            }
        }
    } while (-not $done)
    Write-Host "    State: $($res.state) @ $($res.browser_download_url)"
    if ($res.name -cne $name) {
        Write-Error "    Uploaded asset has different name than expected. Is: '$($res.name)'. Expected: '$name'."
    }
}
Write-Host "Done" -ForegroundColor Green
