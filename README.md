# publish-catpkg
GitHub Action to publish (compile and upload to a release)
all catpkg assets: indexes and datafiles.

It compiles all repository's cat/gst files into catz/gstz zipped format,
indexes them and saves the indexes in various formats: `bsi`,`bsr`,`catpkg.json`.

Those assets are then uploaded to the specified release upload URL. Old
duplicate assets are deleted if they exist.

## Usage

```yml
on:
  release:
    types: [created, edited]
jobs:
  publish-catpkg:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: BSData/publish-catpkg@v1
        with:
        # GitHub OAuth token to authorize API requests for upload of assets
        # (and deletion of existing duplicates)
        # Default: github.token
        token: ''
        
        # Path to a 'staging' folder where assets will be saved before upload
        # Default: runner.temp/assets
        staging-path: ''

        # Hypermedia URL to upload assets to, as retrieved from releases API
        # Default: github.event.release.upload_url
        upload-url: ''
```

## Credits

The action was built based on https://github.com/ebekker/pwsh-github-action-base

GitHubActionsCore.psm1 taken from https://github.com/Amadevus/pwsh-script
