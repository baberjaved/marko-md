<#
  Builds Marko for Windows.

    .\app\windows\build.ps1              -> app\windows\build\publish\Marko.exe  (+ viewer\ folder)
    .\app\windows\build.ps1 -Install     -> also installs to %LOCALAPPDATA%\Marko, adds a Start Menu shortcut, registers .md
    .\app\windows\build.ps1 -Install -Default -> ...and opens Windows' Default Apps page for Marko
    .\app\windows\build.ps1 -Zip         -> also produces app\windows\build\Marko-<version>-win-x64.zip

  Needs: .NET 8 SDK (https://dot.net) and Node. Framework-dependent build (~2 MB); the .NET 8 Desktop Runtime and the
  WebView2 Runtime are both standard on Windows 10/11 and the exe prompts to install them if missing.
  Add -SelfContained for a ~70 MB build that needs no runtime.
#>
param([switch]$Install, [switch]$Default, [switch]$Zip, [switch]$SelfContained, [string]$Arch = "x64")
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Here "..\..")
$Out  = Join-Path $Here "build"
$Pub  = Join-Path $Out "publish"
$Version = (Get-Content (Join-Path $Root "package.json") | ConvertFrom-Json).version
Write-Host "> Marko for Windows v$Version ($Arch)"
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "dotnet not found - install the .NET 8 SDK from https://dot.net" }

# 1. Viewer build + vendored libraries (so the app is fully offline)
Push-Location $Root; node scripts/build.js | Out-Null; Pop-Location
$ViewerDir = Join-Path $Here "viewer"; $Vendor = Join-Path $ViewerDir "vendor"
New-Item -ItemType Directory -Force -Path $Vendor | Out-Null
Copy-Item (Join-Path $Root "viewer\marko.html") (Join-Path $ViewerDir "marko.html") -Force
Copy-Item (Join-Path $Root "docs\guide.md") (Join-Path $ViewerDir "guide.md") -Force
$libs = @{
  "marked.min.js"    = "https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"
  "highlight.min.js" = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
  "mermaid.min.js"   = "https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js"
}
$cache = Join-Path $Here "vendor-cache"; New-Item -ItemType Directory -Force -Path $cache | Out-Null
foreach ($name in $libs.Keys) {
  $c = Join-Path $cache $name
  if (-not (Test-Path $c) -or (Get-Item $c).Length -eq 0) { Invoke-WebRequest -Uri $libs[$name] -OutFile $c -UseBasicParsing }
  Copy-Item $c (Join-Path $Vendor $name) -Force
}
$html = Get-Content (Join-Path $ViewerDir "marko.html") -Raw
foreach ($name in $libs.Keys) { $html = $html.Replace($libs[$name], "vendor/$name") }
Set-Content -Path (Join-Path $ViewerDir "marko.html") -Value $html -NoNewline -Encoding UTF8

# 2. Publish
$sc = if ($SelfContained) { "true" } else { "false" }
Write-Host "> dotnet publish (self-contained: $sc)"
dotnet publish (Join-Path $Here "Marko.csproj") -c Release -r "win-$Arch" --self-contained $sc `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:Version=$Version -o $Pub | Out-Null
Write-Host "> built $Pub\Marko.exe ($([math]::Round((Get-Item "$Pub\Marko.exe").Length/1MB,1)) MB)"

# 3. Optional install / zip
if ($Install) {
  $Target = Join-Path $env:LOCALAPPDATA "Marko"
  Get-Process Marko -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  Copy-Item "$Pub\*" $Target -Recurse -Force
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Programs")) "Marko.lnk"))
  $lnk.TargetPath = "$Target\Marko.exe"; $lnk.WorkingDirectory = $Target; $lnk.IconLocation = "$Target\Marko.exe,0"; $lnk.Description = "Marko - Markdown viewer"; $lnk.Save()
  & "$Target\Marko.exe" --register
  Write-Host "> installed to $Target (Start Menu shortcut added, registered for .md files)"
  if ($Default) { & "$Target\Marko.exe" --set-default; Write-Host "> pick Marko for .md in the Default Apps page that just opened" }
}
if ($Zip) {
  $ZipPath = Join-Path $Out "Marko-$Version-win-$Arch.zip"
  if (Test-Path $ZipPath) { Remove-Item $ZipPath }
  Compress-Archive -Path "$Pub\*" -DestinationPath $ZipPath
  Write-Host "> $ZipPath"
}
Write-Host "done. Run it:  $Pub\Marko.exe path\to\file.md"
