#!/usr/bin/env pwsh
if (-not (Test-Path node_modules -PathType Container))
{
    npm install
}
npx @zeit/ncc build ./invoke-pwsh.js -o dist -m --no-source-map-register