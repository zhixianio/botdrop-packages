# Protected Packages

This directory contains .deb packages that are NOT compiled by the Termux build system
but must always be included in the BotDrop APT repository.

These packages are manually built or sourced from upstream releases.
When rebuilding gh-pages from scratch, scripts MUST preserve these packages.

## How to add a protected package

1. Place the .deb file in this directory
2. It will be automatically included when rebuilding the APT repo

## Current protected packages

- `sharp-node-addon` - Pre-built sharp native addon from sharp releases
