#
# Module manifest for module 'BsdataCatpkg'
#
# Generated by: Amadeusz Sadowski
#
# Generated on: 01.06.2020
#
# Author of this module
# Author = 'Amadeusz Sadowski'
#
# # Company or vendor of this module
# CompanyName = 'BSData'
#
# # Copyright statement for this module
# Copyright = '(c) BSData. All rights reserved.'

#Requires -Version 7

filter CallNative {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [scriptblock] $Command,

        [Parameter()]
        [switch] $PrintCommand,

        [Parameter()]
        [switch] $OutHost
    )
    if ($PrintCommand) {
        Write-Host "$Command".Trim() -ForegroundColor Cyan
    }
    $global:LASTEXITCODE = 0
    if ($OutHost) {
        . $Command | Out-Host
    }
    else {
        . $Command
    }
    if ($global:LASTEXITCODE -ne 0) {
        Write-Error "Native executable failed with exit code $($global:LASTEXITCODE): $("$Command".Trim())"
    }
}

function Build-BsdataReleaseAssets {
    [CmdletBinding()]
    param (
        # Path where the repository is located, defaults to current directory.
        [Parameter()]
        [string]
        $Path,
        # Path to an asset staging directory.
        [Parameter()]
        [string]
        $StagingPath = './staged',
        # GitHub repository with owner in the following format: 'owner/repository_name'.
        [Parameter(Mandatory)]
        [string]
        $Repository,
        # Repository display name, defaults to repository name.
        [Parameter()]
        [string]
        $RepositoryDisplayName,
        # Repository website URL, defaults to 'https://github.com/$Repository'.
        [Parameter()]
        [string]
        $RepositoryUrl,
        # Release details.
        [Parameter(Mandatory)]
        [object]
        $Release
    )
    
    $Path ??= [string](Get-Location)
    $repo = ($Repository -split '/')[1]
    $tag = $Release.tag_name
    $RepositoryDisplayName ??= $repo
    $RepositoryUrl ??= "https://github.com/$Repository"
    $PSDefaultParameterValues["Get-GitHubUrl:RepositoryUrl"] = $RepositoryUrl

    Push-Location -LiteralPath $Path
    try {
        # check if there are any cat/gst files to process, otherwise short-circuit out
        if ((Get-ChildItem -Recurse -Include *.cat, *.gst -File).Length -eq 0) {
            Write-Host "No datafiles to process and publish." -ForegroundColor Green
            return
        }

        # install wham if necessary
        $wham = "$PSScriptRoot/lib/wham"
        if ($null -eq (Get-Command $wham -ErrorAction:Ignore)) {
            $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 1
            $env:DOTNET_NOLOGO = 1
            $env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
            {
                dotnet tool install wham --version 0.13.0 --tool-path "$PSScriptRoot/lib"
            } | CallNative -PrintCommand -OutHost
        }

        # create catz/gstz files
        {
            & $wham publish -a zip -o $StagingPath
        } | CallNative -PrintCommand -OutHost

        # rename files so that they have release asset-compatible names, save mappings
        $datafiles = Get-ChildItem -LiteralPath $StagingPath -Recurse -Include *.catz, *.gstz -File | ForEach-Object {
            # drop 'z' from extension
            $OriginalName = $_.Name.Remove($_.Name.Length - 1)
            $File = $_ | Rename-Item -NewName (Get-EscapedAssetName $_.Name) -PassThru
            return @{
                originalName = $OriginalName
                file         = $File
            }
        }
        $datafiles | ForEach-Object {
            Write-Host "Staged '$($_.originalName)' as '$($_.file.Name)'" -ForegroundColor Green
        }
        $taggedAssetNameEscaped = Get-EscapedAssetName "$repo.$tag"
        $latestAssetNameEscaped = Get-EscapedAssetName "$repo.latest"

        # publish indexes based on catz/gstz datafiles (already renamed)
        Push-Location -LiteralPath $StagingPath
        try {
            $repoName = $RepositoryDisplayName
            $tagBsiUrl = Get-GitHubUrl "$taggedAssetNameEscaped.bsi" $tag
            $latestBsiUrl = Get-GitHubUrl "$latestAssetNameEscaped.bsi" -LatestReleaseAsset
            @(
                # 'tag' assets: create '$repo.$tag.bsr'
                { & $wham publish -a bsr -f $taggedAssetNameEscaped --repo-name $repoName },
                # 'tag' assets: create '$repo.$tag.bsi'
                { & $wham publish -a bsi -f $taggedAssetNameEscaped --repo-name $repoName --url $tagBsiUrl },
                # 'latest' assets: create '$repo.latest.bsi'
                { & $wham publish -a bsi -f $latestAssetNameEscaped --repo-name $repoName --url $latestBsiUrl }
            ) | CallNative -PrintCommand -OutHost
        }
        finally {
            Pop-Location
        }

        $bugTrackerUrl = $RepositoryUrl + '/issues'
        $reportBugUrl = 'http://battlescribedata.appspot.com/#/repo/' + $repo
        $catpkgJsonFilename = Get-EscapedAssetName "$repo.catpkg.json"
        $catpkgGzipFilename = $catpkgJsonFilename + '.gz'
        $bsiUrl = Get-GitHubUrl "$latestAssetNameEscaped.bsi" -LatestReleaseAsset
        $catpkgUrl = Get-GitHubUrl $catpkgJsonFilename -LatestReleaseAsset
        $catpkgGzipUrl = Get-GitHubUrl $catpkgGzipFilename -LatestReleaseAsset
        $bsrUrl = Get-GitHubUrl "$taggedAssetNameEscaped.bsr" $tag

        # build '$repo.catpkg.json' content
        # based on https://github.com/BSData/bsdata/blob/82415028d9d63fe7a3372811942f6ec277ed649a/src/main/java/org/battlescribedata/dao/GitHubDao.java#L939-L957
        $catpkg = [ordered]@{
            '$schema'             = 'https://raw.githubusercontent.com/BSData/schemas/master/src/catpkg.schema.json'
            name                  = $repo
            description           = $RepositoryDisplayName
            battleScribeVersion   = $null # set below
            version               = $tag
            lastUpdated           = $Release.created_at
            lastUpdateDescription = $Release.name
            indexUrl              = $bsiUrl
            repositoryUrl         = $catpkgUrl
            repositoryGzipUrl     = $catpkgGzipUrl
            repositoryBsrUrl      = $bsrUrl
            githubUrl             = $RepositoryUrl
            feedUrl               = $RepositoryUrl + '/releases.atom'
            bugTrackerUrl         = $bugTrackerUrl
            reportBugUrl          = $reportBugUrl
            repositoryFiles       = @($datafiles | ForEach-Object {
                    # considered reading index.bsi, but loading zip to memory in powershell
                    # required using .net types and was messy
                    # also it's expected wham will take over creation of catpkg json in future
                    # based on https://github.com/BSData/bsdata/blob/82415028d9d63fe7a3372811942f6ec277ed649a/src/main/java/org/battlescribedata/dao/GitHubDao.java#L886-L911
                    $nonzipFilename = $_.originalName
                    $xml = if (Test-Path -LiteralPath $nonzipFilename) { [xml](Get-Content -LiteralPath $nonzipFilename) }
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
                        fileUrl             = Get-GitHubUrl $_.file.Name $tag
                        githubUrl           = Get-GitHubUrl $nonzipFilename -Blob $Release.target_commitish
                        bugTrackerUrl       = $bugTrackerUrl
                        reportBugUrl        = $reportBugUrl
                        authorName          = $root.authorName
                        authorContact       = $root.authorContact
                        authorUrl           = $root.authorUrl
                        sourceSha256        = (Get-FileHash -LiteralPath $nonzipFilename 'SHA256').Hash
                    }
                })
        }
        # select "highest" version via lexicographical (alphanumeric) order from amongst the files'
        $catpkg.battleScribeVersion = $catpkg.repositoryFiles.battleScribeVersion | Sort-Object -Bottom 1

        # save json to file
        $catpkgPath = Join-Path $StagingPath $catpkgJsonFilename
        $catpkg | ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii | Set-Content -LiteralPath $catpkgPath
        # gzip catpkg
        $catpkgPath | Compress-GZip

        return Get-ChildItem -LiteralPath $StagingPath -Include *.json, *.json.gz, *.bsi, *.bsr, *.gstz, *.catz -Recurse -File | Sort-Object -Property Name
    }
    finally {
        Pop-Location
    }
}

function Publish-GitHubReleaseAsset {
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Assets to upload
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]
        $Path,
        # Release asset upload URL
        [Parameter(Mandatory)]
        [string]
        $UploadUrl,
        # Release assets URL
        [Parameter(Mandatory, ParameterSetName = 'Forced')]
        [string]
        $AssetsUrl,
        # Force asset upload even if it already exists by deleting it beforehand.
        [Parameter(Mandatory, ParameterSetName = 'Forced')]
        [switch]
        $Force,
        # GitHub API Auth token. Defaults to $env:GITHUB_TOKEN.
        [Parameter()]
        [string]
        $Token = $env:GITHUB_TOKEN
    )
    
    begin {
        $authHeaders = @{
            Headers = @{
                Authorization = "token $token"
            }
        }
        if ($Force) {
            # get previous assets
            $previousAssets = Invoke-RestMethod $AssetsUrl @authHeaders -FollowRelLink | ForEach-Object { $_ }
        }
    }
    
    process {
        # upload assets (delete old ones with the same name first if $Force)
        $Path | ForEach-Object {
            $file = Get-Item -LiteralPath $_
            $name = $file.Name
            $mime = 'application/octet-stream'
            if ($Force) {
                $duplicate = $previousAssets | Where-Object name -eq $name | Select-Object -First 1
                if ($duplicate -and $PSCmdlet.ShouldProcess($name, "DELETE " + $duplicate.url)) {
                    # delete duplicate first
                    Invoke-RestMethod $duplicate.url -Method Delete @authHeaders -SkipHttpErrorCheck -ErrorAction:Ignore | Out-Null
                }
            }
            $apiArgs = @{
                Method            = 'POST'
                Uri               = Expand-UriTemplate $UploadUrl @{ name = $name }
                InFile            = $file.FullName
                ContentType       = $mime
                RetryIntervalSec  = 5
                MaximumRetryCount = 5
            }
            if ($PSCmdlet.ShouldProcess($file.FullName, $apiArgs.Method + " " + $apiArgs.Uri)) {
                $res = Invoke-RestMethod @apiArgs @authHeaders
                Write-Information "    State: $($res.state) @ $($res.browser_download_url)"
                if ($res.name -cne $name) {
                    Write-Error "    Uploaded asset has different name than expected. Is: '$($res.name)'. Expected: '$name'."
                }
            }
        }
    }
}

# this function compresses input files as .gz files
function Compress-GZip {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Specifies a path to one or more locations.
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Path to one or more locations.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,
        # Force overwrite of existing gzipped file
        [Parameter()]
        [switch]
        $Force,
        # Return FileInfo of the gzipped file
        [Parameter()]
        [switch]
        $PassThru
    )
    process {
        $Path | ForEach-Object {
            $original = $_
            $gzip = "$_.gz"
            if ($PSCmdlet.ShouldProcess($original)) {
                $inputFile = Get-Item -LiteralPath $original
                $outputFile = New-Item $gzip -Force:$Force
                if (-not $outputFile) {
                    return
                }
                try {
                    $inputStream = [System.IO.File]::OpenRead($inputFile.FullName)
                    $outputStream = [System.IO.File]::OpenWrite($outputFile.FullName)
                    $gzipStream = [System.IO.Compression.GZipStream]::new($outputStream, [System.IO.Compression.CompressionMode]'Compress')
                    $inputStream.CopyToAsync($gzipStream).Wait()
                }
                finally {
                    $gzipStream.Dispose()
                    $outputStream.Dispose()
                }
                if ($PassThru) {
                    return $outputFile
                }
            }
        }
    }
}

# this function builds a github download url
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
        [string] $RepositoryUrl
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
    return "$RepositoryUrl/$middleSegment/$escapedName"
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
    $periodsOnly = $Name -creplace '[^a-zA-Z0-9\-_]+', '.'
    # 2. remove any leading or trailing period
    return $periodsOnly.Trim('.')
}

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

Export-ModuleMember Build-BsdataReleaseAssets, Publish-GitHubReleaseAsset
