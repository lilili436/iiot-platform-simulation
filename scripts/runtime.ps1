function Get-BundledRuntime([ValidateSet("java","python","node")][string]$Name){
 if([Environment]::OSVersion.Platform -ne "Win32NT" -or [Environment]::OSVersion.Version.Major -lt 10 -or ![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq "ARM64"){
  throw "Bundled runtimes require Windows 10/11 Intel/AMD x64."
 }
 $repoRoot=Split-Path $PSScriptRoot -Parent
 $bundle=Join-Path $repoRoot "environment\runtime-win-x64"
 $manifest=Get-Content -LiteralPath (Join-Path $bundle "manifest.json") -Raw -Encoding UTF8|ConvertFrom-Json
 $package=@($manifest.packages|Where-Object{$_.name -eq $Name})[0]
 if(!$package){throw "Bundled runtime missing: $Name"}
 $cache=Join-Path $repoRoot "environment\.runtime"
 $destination=Join-Path $cache $package.directory
 $stamp=Join-Path $destination ".ready"
 $ready=(Test-Path -LiteralPath $stamp) -and ((Get-Content -LiteralPath $stamp -Raw).Trim() -eq $package.sha256)
 if(!$ready){
  if(Test-Path -LiteralPath $destination){throw "Incomplete/outdated runtime at $destination. Rename that folder, then retry; project files are preserved."}
  $archive=Join-Path $bundle $package.archive
  if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.sha256){throw "Runtime archive checksum mismatch: $Name. Download and extract the complete project again."}
  New-Item -ItemType Directory -Path $cache -Force|Out-Null
  Write-Host "Preparing bundled $Name $($package.version) (first use)..."
  Expand-Archive -LiteralPath $archive -DestinationPath $destination
  foreach($file in $package.executables){
   if((Get-FileHash -LiteralPath (Join-Path $destination $file) -Algorithm SHA256).Hash -ne $package.file_sha256.$file){throw "Extracted runtime checksum mismatch: $Name/$file"}
  }
  [IO.File]::WriteAllText($stamp,$package.sha256,[Text.UTF8Encoding]::new($false))
 }
 foreach($file in $package.executables){if(!(Test-Path -LiteralPath (Join-Path $destination $file))){throw "Runtime file missing: $Name/$file. Re-extract the complete project."}}
 return $destination
}
