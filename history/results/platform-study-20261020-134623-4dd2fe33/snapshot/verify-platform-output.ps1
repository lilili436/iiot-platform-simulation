[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BatchDir)
$ErrorActionPreference="Stop"
$BatchDir=(Resolve-Path -LiteralPath $BatchDir).Path
$manifest=Get-Content -LiteralPath (Join-Path $BatchDir "manifest.json") -Raw -Encoding utf8 | ConvertFrom-Json
$rows=@(Import-Csv -LiteralPath (Join-Path $BatchDir "runs.csv") -Encoding utf8)
if($rows.Count -ne $manifest.expected_runs){throw "Run count mismatch"}
function Tokens([string]$text) { return @($text.Split("|") | Where-Object { $_ -ne "" }) }
function Has-Missing([string]$required,[string]$actual) {
    $a=@(Tokens $actual)
    return @((Tokens $required) | Where-Object { $_ -notin $a }).Count -gt 0
}
$verified=@()
foreach($r in $rows) {
    $case="c{0:D2}-{1}-{2}-{3}-r{4:D2}" -f [int]$r.chain_count,$r.capability_profile,$r.compatibility_mode,$r.algorithm,[int]$r.repeat_index
    $details=@(Import-Csv -LiteralPath (Join-Path $BatchDir "audits\$case.assignments.csv") -Encoding utf8)
    if($details.Count -ne [int]$r.accepted){throw "Assignment count mismatch: $case"}
    $local=@{}; $effective=@{}; $ids=@{}
    $counts=@{ARCH_MISMATCH=0;RUNTIME_UNSUPPORTED=0;API_MISSING=0;DRIVER_MISSING=0;SECURITY_POLICY_MISMATCH=0}
    $violations=0
    foreach($d in $details) {
        if($ids.ContainsKey($d.service_id)){throw "Duplicate assignment"}
        $ids[$d.service_id]=$true
        if($d.service_id -notmatch '^(collect|preprocess|detect|alert)-c([1-9][0-9]*)$' -or [int]$Matches[2] -gt [int]$r.chain_count){throw "Unknown service identity"}
        if($d.ready -ne "true"){throw "Accepted assignment did not become READY"}
        $codes=@()
        if($d.required_arch -ne $d.node_arch){$codes+="ARCH_MISMATCH"}
        if($d.required_runtime -notin @(Tokens $d.node_runtimes)){$codes+="RUNTIME_UNSUPPORTED"}
        if(Has-Missing $d.required_apis $d.node_apis){$codes+="API_MISSING"}
        if(Has-Missing $d.required_drivers $d.node_drivers){$codes+="DRIVER_MISSING"}
        if(Has-Missing $d.required_security $d.node_security){$codes+="SECURITY_POLICY_MISMATCH"}
        if(($codes -join "|") -ne $d.violation_codes){throw "Violation code mismatch: $case / $($d.service_id)"}
        foreach($code in $codes){$counts[$code]++}
        if($codes.Count){$violations++}else{$local[$d.service_id]=$true;$effective[$d.service_id]=$true}
        if(($d.locally_compliant -eq "true") -ne ($codes.Count -eq 0)){throw "Local compliance mismatch"}
    }
    # Independent closure using this experiment's four-stage chain specification.
    foreach($chain in 1..[int]$r.chain_count) {
        $upstream=$true
        foreach($stage in @("collect","preprocess","detect","alert")) {
            $id="$stage-c$chain"
            if(!$effective.ContainsKey($id)){$upstream=$false}
            if(!$upstream){$effective.Remove($id)}
        }
    }
    $workflows=0
    foreach($chain in 1..[int]$r.chain_count) {
        if(@(@("collect","preprocess","detect","alert") | Where-Object { !$effective.ContainsKey("$_-c$chain") }).Count -eq 0){$workflows++}
    }
    foreach($d in $details){
        if(($d.compliant_ready -eq "true") -ne $effective.ContainsKey($d.service_id)){throw "Dependency closure mismatch"}
    }
    if($violations -ne [int]$r.violating_assignments -or $local.Count -ne [int]$r.locally_compliant_ready -or
        $effective.Count -ne [int]$r.compliant_ready -or $workflows -ne [int]$r.compliant_workflows){throw "Summary audit mismatch: $case"}
    $fieldMap=@{ARCH_MISMATCH="arch_mismatch_count";RUNTIME_UNSUPPORTED="runtime_missing_count";API_MISSING="api_missing_count";DRIVER_MISSING="driver_missing_count";SECURITY_POLICY_MISMATCH="security_mismatch_count"}
    foreach($code in $counts.Keys){if($counts[$code] -ne [int]$r.($fieldMap[$code])){throw "Reason category count mismatch"}}
    $candidates=@(Import-Csv -LiteralPath (Join-Path $BatchDir "audits\$case.candidates.csv") -Encoding utf8)
    if($candidates.Count -ne 66*[int]$r.chain_count){throw "Incomplete initial candidate audit"}
    $verified+=[pscustomobject]@{case_id=$case; assignments=$details.Count; candidates=$candidates.Count; audit_verified=$true}
}
$verified | Export-Csv -LiteralPath (Join-Path $BatchDir "audit-checks.csv") -NoTypeInformation -Encoding utf8
Write-Host "Independent audit checks passed: $($verified.Count)/$($rows.Count)"
