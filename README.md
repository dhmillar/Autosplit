# Autosplit for WoW Retail

<img src="assets/autosplit-icon.png" alt="Autosplit icon" width="96">

Autosplit breaks a stack into individual items with Ctrl-click and helps hand out a chosen quantity to each eligible raid member once per raid night. You still review and accept each trade through Blizzard's UI.

## Install

- **WowUp:** Select your World of Warcraft Retail client. Under **Get Addons > Install from URL**, paste https://github.com/dhmillar/Autosplit.
- **Manual:** Download the installable ZIP from [Releases](https://github.com/dhmillar/Autosplit/releases/latest) and extract it into your Retail Interface/AddOns folder. Keep the Autosplit folder intact. Do not use GitHub's automatically generated source ZIP.

For WoW Retail 12.1.5 (interface 120105). Supports Blizzard's bags and optional Baganator integration, not Classic or Forever. Existing character settings stay in place.

Open the addon with /as or the minimap button. See the [user guide](Autosplit/README.md) for controls, safety checks and trade limitations.

## Build and test

Run tools/New-Release.ps1 in PowerShell to create the installable archive in dist. From the Autosplit folder, the Lua 5.1 regression specs in ../tests exercise the splitting, raid, and UI logic with simulated inventory and trade events.
