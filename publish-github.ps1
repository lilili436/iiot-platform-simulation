[CmdletBinding()]
param()
$ErrorActionPreference="Stop"
$owner="lilili436";$name="iiot-platform-simulation"
$url="https://github.com/$owner/$name.git"
$api="https://api.github.com"
$git=(Get-Command git -ErrorAction Stop).Source
Push-Location -LiteralPath $PSScriptRoot
$oldInteractive=$env:GCM_INTERACTIVE
try{
 if(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot ".git"))){throw "Local Git snapshot missing."}
 $dirty=& $git status --porcelain
 if($LASTEXITCODE -ne 0 -or $dirty){throw "Working tree must be clean. Review and commit changes before uploading."}
 $head=(& $git rev-parse HEAD).Trim()
 # Existing credential only. Never print or write credentials to a file.
 $env:GCM_INTERACTIVE="Never"
 $credentialInput="protocol=https`nhost=github.com`nusername=$owner`n`n"
 $credentialLines=@($credentialInput | & $git -c credential.interactive=false credential fill 2>$null)
 if($LASTEXITCODE -ne 0){throw "GitHub login required. Run: git credential-manager github login --username lilili436 --device ; then run this script again. Do not paste your password/token into chat."}
 $credential=@{}
 foreach($line in $credentialLines){$parts=$line -split "=",2;if($parts.Count -eq 2){$credential[$parts[0]]=$parts[1]}}
 if(!$credential.ContainsKey("password")){throw "GitHub credential unavailable."}
 $headers=@{Authorization="Bearer "+$credential["password"];Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28";"User-Agent"="iiot-handoff"}
 $profile=Invoke-RestMethod -Uri "$api/user" -Headers $headers
 if($profile.login -ne $owner){throw "Authenticated GitHub account differs from lilili436; no remote changes made."}
 $remote=$null
 try{$remote=Invoke-RestMethod -Uri "$api/repos/$owner/$name" -Headers $headers}
 catch{if([int]$_.Exception.Response.StatusCode -ne 404){throw "Cannot inspect target repository; check GitHub authorization/network."}}
 if(!$remote){
  $body=@{name=$name;description="Industrial microservice deployment, fault recovery simulation and evaluation handoff";private=$false;auto_init=$false}|ConvertTo-Json
  $remote=Invoke-RestMethod -Uri "$api/user/repos" -Method Post -Headers $headers -ContentType "application/json" -Body $body
 }
 if($remote.private -or $remote.owner.login -ne $owner){throw "Existing repository does not match the authorized PUBLIC repository. No visibility was changed."}
 $refs=@(& $git ls-remote $url)
 if($LASTEXITCODE -ne 0){throw "Cannot read remote Git references."}
 if($refs.Count -gt 0){
  $main=@($refs|Where-Object{$_ -match "refs/heads/main$"})
  if($main.Count -ne 1 -or ($main[0] -split "\s+")[0] -ne $head){throw "Remote already contains different commits. Stopped without overwriting remote content."}
 }
 $existing=& $git remote get-url origin 2>$null
 if($LASTEXITCODE -eq 0){if($existing.Trim() -ne $url){throw "Existing origin differs; stopped without changing it."}}
 else{& $git remote add origin $url;if($LASTEXITCODE -ne 0){throw "Failed to add origin."}}
 & $git push --set-upstream origin main
 if($LASTEXITCODE -ne 0){throw "Push failed; local files and commit preserved."}
 $verified=Invoke-RestMethod -Uri "$api/repos/$owner/$name" -Headers $headers
 $branch=Invoke-RestMethod -Uri "$api/repos/$owner/$name/branches/main" -Headers $headers
 if($verified.private -or $branch.commit.sha -ne $head){throw "Remote verification failed; inspect GitHub before sharing."}
 $receipt=@{url=$verified.html_url;visibility="public";commit=$head;verified_at=(Get-Date).ToString("o")}|ConvertTo-Json
 $receipt|Set-Content -LiteralPath (Join-Path $PSScriptRoot "environment\upload-receipt.json") -Encoding UTF8
 Write-Host "UPLOAD VERIFIED: $($verified.html_url)"
 Write-Host "DOWNLOAD: $($verified.html_url)/archive/refs/heads/main.zip"
}finally{
 $headers=$null;$credential=$null;$credentialLines=$null
 $env:GCM_INTERACTIVE=$oldInteractive
 Pop-Location
}
