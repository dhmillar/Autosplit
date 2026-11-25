param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$addon=Join-Path $root 'Autosplit'
$names=@('Autosplit.toc','Engine.lua','Autosplit.lua','RaidEngine.lua','RaidGiveaway.lua','RaidWindow.lua','Icon.tga','README.md')
$actual=@(Get-ChildItem -LiteralPath $addon -Force)
if(Compare-Object ($actual.Name|Sort-Object) ($names|Sort-Object)){throw 'Unexpected addon files'}
if($actual|Where-Object {$_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}){throw 'Runtime files must be regular files'}
$toc=Get-Content -LiteralPath (Join-Path $addon 'Autosplit.toc') -Raw
$version=[regex]::Match($toc,'(?m)^## Version: (\d+\.\d+\.\d+)\s*$').Groups[1].Value
$interface=[regex]::Match($toc,'(?m)^## Interface: (\d{6})\s*$').Groups[1].Value
if(!$version -or !$interface -or [int]$interface -lt 120000 -or [int]$interface -ge 160000){throw 'Expected a version and a Retail interface'}
foreach($line in ($toc -split '\r?\n')){if($line -match '\.(lua|xml)$' -and $line -notin $names){throw "Unpackaged TOC entry: $line"}}
if(!$OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$zip=Join-Path $OutputDirectory "Autosplit-$version.zip"
if(Test-Path -LiteralPath $zip){throw 'Destination already exists'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($addon,$zip,[IO.Compression.CompressionLevel]::Optimal,$true)
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try{
  $entries=@($archive.Entries|Where-Object Name)
  if(Compare-Object ($entries.FullName.Replace('\','/')|Sort-Object) ($names|ForEach-Object {"Autosplit/$_"}|Sort-Object)){throw 'Unexpected zip layout'}
  foreach($entry in $entries){
    $s=$entry.Open()
    try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($s))}finally{$s.Dispose()}
    if($hash -ne (Get-FileHash -LiteralPath (Join-Path $addon $entry.Name)).Hash){throw "Incorrect package content: $($entry.Name)"}
  }
}finally{$archive.Dispose()}
Get-FileHash -LiteralPath $zip -Algorithm SHA256
