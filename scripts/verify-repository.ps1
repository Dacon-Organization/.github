[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")]
  [string] $Repository,

  [ValidateSet("Solo", "Team")]
  [string] $Mode = "Solo",

  [ValidateSet("Disabled", "Active")]
  [string] $ExpectedRulesetEnforcement = "Active",

  [string[]] $RequiredStatusChecks = @(
    "CI / gate",
    "PR Policy / gate",
    "Dependency Review / gate"
  ),

  [string[]] $AllowedActionPatterns = @(
    "astral-sh/ruff-action@278981a28ce3188b1e39527901f38254bf3aac89",
    "astral-sh/setup-uv@11f9893b081a58869d3b5fccaea48c9e9e46f990",
    "DavidAnson/markdownlint-cli2-action@8de2aa07cae85fd17c0b35642db70cf5495f1d25",
    "lycheeverse/lychee-action@e7477775783ea5526144ba13e8db5eec57747ce8"
  ),

  [switch] $AllowLegacyBranchProtection
)

$ErrorActionPreference = "Stop"
$apiVersion = "2026-03-10"
$rulesetName = "main-pr-ci"
$errors = New-Object Collections.Generic.List[string]
$warnings = New-Object Collections.Generic.List[string]

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI(gh)가 필요합니다."
}
if ($Repository.Split("/", 2)[0] -ne "Dacon-Organization") {
  throw "안전을 위해 Dacon-Organization 소유 저장소만 검증할 수 있습니다."
}

function Invoke-GhGet {
  param(
    [Parameter(Mandatory = $true)] [string] $Endpoint,
    [switch] $AllowNotFound
  )

  $arguments = @(
    "api",
    "--method", "GET",
    "-H", "Accept: application/vnd.github+json",
    "-H", "X-GitHub-Api-Version: $apiVersion",
    $Endpoint
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $raw = & gh @arguments 2>&1
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorActionPreference
  $text = ($raw | Out-String).Trim()
  if ($exitCode -ne 0) {
    if ($AllowNotFound -and $text -match "HTTP 404") {
      return $null
    }
    throw "GitHub API 실패: GET $Endpoint`n$text"
  }
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }
  return $text | ConvertFrom-Json
}

function Test-StringSetEqual {
  param([object[]] $Left, [object[]] $Right)
  $leftSet = @($Left | ForEach-Object { [string] $_ } | Sort-Object -Unique)
  $rightSet = @($Right | ForEach-Object { [string] $_ } | Sort-Object -Unique)
  if ($leftSet.Count -eq 0 -and $rightSet.Count -eq 0) {
    return $true
  }
  if ($leftSet.Count -eq 0 -or $rightSet.Count -eq 0) {
    return $false
  }
  return @(Compare-Object -ReferenceObject $leftSet -DifferenceObject $rightSet).Count -eq 0
}

function Add-Check {
  param([bool] $Condition, [string] $Message)
  if (-not $Condition) {
    $errors.Add($Message)
  }
}

$repositoryState = Invoke-GhGet -Endpoint "/repos/$Repository"
Add-Check ($repositoryState.visibility -eq "public") "저장소가 Public이 아닙니다."
Add-Check ($repositoryState.default_branch -eq "main") "기본 브랜치가 main이 아닙니다."
Add-Check ([bool] $repositoryState.allow_squash_merge) "squash merge가 비활성입니다."
Add-Check (-not [bool] $repositoryState.allow_merge_commit) "merge commit이 허용되어 있습니다."
Add-Check (-not [bool] $repositoryState.allow_rebase_merge) "rebase merge가 허용되어 있습니다."
Add-Check ([bool] $repositoryState.allow_auto_merge) "auto-merge가 비활성입니다."
Add-Check ([bool] $repositoryState.delete_branch_on_merge) "merge 후 branch 삭제가 비활성입니다."
Add-Check ([bool] $repositoryState.allow_update_branch) "Update branch가 비활성입니다."
Add-Check ($repositoryState.squash_merge_commit_title -eq "PR_TITLE") "squash 제목 정책이 PR_TITLE이 아닙니다."
Add-Check ($repositoryState.squash_merge_commit_message -eq "PR_BODY") "squash 본문 정책이 PR_BODY가 아닙니다."
Add-Check ($repositoryState.security_and_analysis.secret_scanning.status -eq "enabled") "secret scanning이 비활성입니다."
Add-Check ($repositoryState.security_and_analysis.secret_scanning_push_protection.status -eq "enabled") "push protection이 비활성입니다."

$actionsState = Invoke-GhGet -Endpoint "/repos/$Repository/actions/permissions"
Add-Check ([bool] $actionsState.enabled) "GitHub Actions가 비활성입니다."
Add-Check ($actionsState.allowed_actions -eq "selected") "Actions 허용 정책이 selected가 아닙니다."
Add-Check ([bool] $actionsState.sha_pinning_required) "Action full SHA 강제가 비활성입니다."

if ($actionsState.allowed_actions -eq "selected") {
  $selectedActions = Invoke-GhGet -Endpoint "/repos/$Repository/actions/permissions/selected-actions"
  Add-Check ([bool] $selectedActions.github_owned_allowed) "GitHub-owned Action이 허용되지 않습니다."
  Add-Check (-not [bool] $selectedActions.verified_allowed) "모든 verified Action이 포괄 허용되어 있습니다."
  $allowlistMatches = Test-StringSetEqual -Left @($selectedActions.patterns_allowed) -Right $AllowedActionPatterns
  Add-Check $allowlistMatches "외부 Action allowlist가 기준과 다릅니다."
}

$workflowPermission = Invoke-GhGet -Endpoint "/repos/$Repository/actions/permissions/workflow"
Add-Check ($workflowPermission.default_workflow_permissions -eq "read") "GITHUB_TOKEN 기본 권한이 read가 아닙니다."
Add-Check (-not [bool] $workflowPermission.can_approve_pull_request_reviews) "GITHUB_TOKEN의 PR 승인 권한이 켜져 있습니다."

$privateReporting = Invoke-GhGet -Endpoint "/repos/$Repository/private-vulnerability-reporting"
Add-Check ([bool] $privateReporting.enabled) "private vulnerability reporting이 비활성입니다."

$rulesets = @(
  Invoke-GhGet -Endpoint "/repos/$Repository/rulesets?includes_parents=false&targets=branch&per_page=100"
)
$matches = @(
  $rulesets | Where-Object {
    $_.name -eq $rulesetName -and $_.source_type -eq "Repository"
  }
)
Add-Check ($matches.Count -eq 1) "repository ruleset '$rulesetName'이 정확히 하나가 아닙니다."

if ($matches.Count -eq 1) {
  $ruleset = Invoke-GhGet -Endpoint "/repos/$Repository/rulesets/$($matches[0].id)"
  Add-Check ($ruleset.enforcement -eq $ExpectedRulesetEnforcement.ToLowerInvariant()) "ruleset enforcement가 기대값과 다릅니다."
  Add-Check ($ruleset.target -eq "branch") "ruleset target이 branch가 아닙니다."
  Add-Check ($ruleset.bypass_actors.Count -eq 0) "ruleset bypass actor가 존재합니다."
  Add-Check ($ruleset.conditions.ref_name.include -contains "~DEFAULT_BRANCH") "ruleset이 기본 브랜치를 대상으로 하지 않습니다."

  $ruleTypes = @($ruleset.rules | ForEach-Object { $_.type })
  foreach ($requiredType in @(
    "deletion",
    "non_fast_forward",
    "required_linear_history",
    "pull_request",
    "required_status_checks"
  )) {
    Add-Check ($ruleTypes -contains $requiredType) "ruleset rule 누락: $requiredType"
  }

  $pullRequestRule = $ruleset.rules | Where-Object { $_.type -eq "pull_request" }
  $expectedApprovalCount = if ($Mode -eq "Team") { 1 } else { 0 }
  $teamMode = $Mode -eq "Team"
  Add-Check ([int] $pullRequestRule.parameters.required_approving_review_count -eq $expectedApprovalCount) "required approval 수가 모드와 다릅니다."
  Add-Check ([bool] $pullRequestRule.parameters.dismiss_stale_reviews_on_push -eq $teamMode) "stale review 정책이 모드와 다릅니다."
  Add-Check ([bool] $pullRequestRule.parameters.require_code_owner_review -eq $teamMode) "CODEOWNERS review 정책이 모드와 다릅니다."
  Add-Check ([bool] $pullRequestRule.parameters.required_review_thread_resolution) "review thread 해결이 필수가 아닙니다."
  Add-Check (Test-StringSetEqual -Left @($pullRequestRule.parameters.allowed_merge_methods) -Right @("squash")) "ruleset merge 방식이 squash-only가 아닙니다."

  $statusRule = $ruleset.rules | Where-Object { $_.type -eq "required_status_checks" }
  $statusContexts = @(
    $statusRule.parameters.required_status_checks | ForEach-Object { $_.context }
  )
  Add-Check (Test-StringSetEqual -Left $statusContexts -Right $RequiredStatusChecks) "required status check 목록이 기준과 다릅니다."
  Add-Check ([bool] $statusRule.parameters.strict_required_status_checks_policy) "strict status check 정책이 비활성입니다."
  if ($ExpectedRulesetEnforcement -eq "Active") {
    foreach ($statusCheck in $statusRule.parameters.required_status_checks) {
      Add-Check ([int] $statusCheck.integration_id -gt 0) "$($statusCheck.context)의 integration ID가 없습니다."
    }
    $effectiveRules = @(Invoke-GhGet -Endpoint "/repos/$Repository/rules/branches/main")
    Add-Check ($effectiveRules.Count -gt 0) "main의 effective rules를 확인할 수 없습니다."
  }
}

$legacyProtection = Invoke-GhGet -Endpoint "/repos/$Repository/branches/main/protection" -AllowNotFound
if ($legacyProtection) {
  if ($AllowLegacyBranchProtection) {
    $warnings.Add("legacy branch protection이 ruleset과 함께 적용되고 있습니다.")
  }
  else {
    $errors.Add("legacy branch protection이 남아 있어 ruleset과 누적 적용됩니다.")
  }
}

foreach ($warning in $warnings) {
  Write-Warning $warning
}
if ($errors.Count -gt 0) {
  Write-Error "저장소 정책 검증 실패:`n- $($errors -join "`n- ")"
  exit 1
}

Write-Host "저장소 정책 검증 통과: $Repository ($Mode/$ExpectedRulesetEnforcement)"
