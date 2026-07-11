[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")]
  [string] $Repository,

  [ValidateSet("Solo", "Team")]
  [string] $Mode = "Solo",

  [ValidateSet("Disabled", "Active")]
  [string] $RulesetEnforcement = "Disabled",

  [string[]] $RequiredStatusChecks = @(
    "CI / gate",
    "PR Policy / gate",
    "Dependency Review / gate"
  ),

  [Nullable[int]] $StatusCheckIntegrationId,

  [string[]] $AllowedActionPatterns = @(
    "astral-sh/ruff-action@278981a28ce3188b1e39527901f38254bf3aac89",
    "astral-sh/setup-uv@11f9893b081a58869d3b5fccaea48c9e9e46f990",
    "DavidAnson/markdownlint-cli2-action@8de2aa07cae85fd17c0b35642db70cf5495f1d25",
    "lycheeverse/lychee-action@e7477775783ea5526144ba13e8db5eec57747ce8"
  ),

  [switch] $RemoveLegacyBranchProtection,
  [switch] $VerifyOnly
)

$ErrorActionPreference = "Stop"
$apiVersion = "2026-03-10"
$rulesetName = "main-pr-ci"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI(gh)가 필요합니다."
}

$owner = $Repository.Split("/", 2)[0]
if ($owner -ne "Dacon-Organization") {
  throw "안전을 위해 Dacon-Organization 소유 저장소만 설정할 수 있습니다."
}

function Invoke-GhApi {
  param(
    [Parameter(Mandatory = $true)] [string] $Endpoint,
    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")] [string] $Method = "GET",
    [object] $Body,
    [switch] $AllowNotFound
  )

  $arguments = @(
    "api",
    "--method", $Method,
    "-H", "Accept: application/vnd.github+json",
    "-H", "X-GitHub-Api-Version: $apiVersion",
    $Endpoint
  )
  $temporaryFile = $null
  try {
    if ($null -ne $Body) {
      $temporaryFile = [IO.Path]::GetTempFileName()
      $json = $Body | ConvertTo-Json -Depth 30 -Compress
      [IO.File]::WriteAllText(
        $temporaryFile,
        $json,
        (New-Object Text.UTF8Encoding($false))
      )
      $arguments += @("--input", $temporaryFile)
    }

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
      throw "GitHub API 실패: $Method $Endpoint`n$text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
      return $null
    }
    return $text | ConvertFrom-Json
  }
  finally {
    if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile)) {
      Remove-Item -LiteralPath $temporaryFile -Force
    }
  }
}

function Test-StringSetEqual {
  param([object[]] $Left, [object[]] $Right)
  $reference = @($Left | ForEach-Object { [string] $_ } | Sort-Object -Unique)
  $differenceSet = @($Right | ForEach-Object { [string] $_ } | Sort-Object -Unique)
  if ($reference.Count -eq 0 -and $differenceSet.Count -eq 0) {
    return $true
  }
  if ($reference.Count -eq 0 -or $differenceSet.Count -eq 0) {
    return $false
  }
  $difference = @(Compare-Object -ReferenceObject $reference -DifferenceObject $differenceSet)
  return $difference.Count -eq 0
}

function Find-StatusCheckIntegrationId {
  param([string[]] $Contexts)

  $candidateShas = New-Object Collections.Generic.List[string]
  $pullRequests = @(
    Invoke-GhApi -Endpoint "/repos/$Repository/pulls?state=open&per_page=30"
  )
  foreach ($pullRequest in $pullRequests) {
    if ($pullRequest.head.sha) {
      $candidateShas.Add([string] $pullRequest.head.sha)
    }
  }

  $commits = @(Invoke-GhApi -Endpoint "/repos/$Repository/commits?per_page=30")
  foreach ($commit in $commits) {
    if ($commit.sha) {
      $candidateShas.Add([string] $commit.sha)
    }
  }

  foreach ($sha in @($candidateShas | Select-Object -Unique)) {
    $response = Invoke-GhApi -Endpoint "/repos/$Repository/commits/$sha/check-runs?per_page=100"
    $successful = @(
      $response.check_runs | Where-Object {
        $Contexts -contains $_.name -and $_.conclusion -eq "success"
      }
    )
    $foundContexts = @($successful | ForEach-Object { $_.name } | Sort-Object -Unique)
    if (-not (Test-StringSetEqual -Left $foundContexts -Right $Contexts)) {
      continue
    }
    $appIds = @($successful | ForEach-Object { $_.app.id } | Sort-Object -Unique)
    if ($appIds.Count -eq 1) {
      Write-Host "성공 check에서 integration ID $($appIds[0])를 확인했습니다."
      return [int] $appIds[0]
    }
  }

  throw "최근 commit에서 모든 필수 check의 성공 기록을 찾지 못했습니다. 먼저 시험 PR을 실행하세요."
}

$verifyPath = Join-Path $PSScriptRoot "verify-repository.ps1"
if ($VerifyOnly) {
  $verifyOnlyParameters = @{
    Repository = $Repository
    Mode = $Mode
    ExpectedRulesetEnforcement = $RulesetEnforcement
    RequiredStatusChecks = $RequiredStatusChecks
    AllowedActionPatterns = $AllowedActionPatterns
  }
  & $verifyPath @verifyOnlyParameters
  if (-not $?) {
    exit 1
  }
  exit 0
}

$repositoryState = Invoke-GhApi -Endpoint "/repos/$Repository"
if ($repositoryState.visibility -ne "public") {
  throw "현재 정책은 Public 저장소에만 적용합니다: $Repository"
}
if ($repositoryState.default_branch -ne "main") {
  throw "기본 브랜치가 main이 아닙니다: $($repositoryState.default_branch)"
}

$legacyProtection = Invoke-GhApi -Endpoint "/repos/$Repository/branches/main/protection" -AllowNotFound
if ($legacyProtection) {
  if ($RulesetEnforcement -eq "Active" -and -not $RemoveLegacyBranchProtection) {
    throw "legacy branch protection이 있습니다. 새 CI 검증 후 -RemoveLegacyBranchProtection을 명시하세요."
  }
  Write-Warning "legacy branch protection을 발견했습니다. ruleset과 누적 적용됩니다."
}

$desiredRepository = [ordered]@{
  allow_squash_merge = $true
  allow_merge_commit = $false
  allow_rebase_merge = $false
  allow_auto_merge = $true
  delete_branch_on_merge = $true
  allow_update_branch = $true
  squash_merge_commit_title = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  security_and_analysis = [ordered]@{
    secret_scanning = @{ status = "enabled" }
    secret_scanning_push_protection = @{ status = "enabled" }
  }
}

$repositoryDrift = (
  -not $repositoryState.allow_squash_merge -or
  $repositoryState.allow_merge_commit -or
  $repositoryState.allow_rebase_merge -or
  -not $repositoryState.allow_auto_merge -or
  -not $repositoryState.delete_branch_on_merge -or
  -not $repositoryState.allow_update_branch -or
  $repositoryState.squash_merge_commit_title -ne "PR_TITLE" -or
  $repositoryState.squash_merge_commit_message -ne "PR_BODY" -or
  $repositoryState.security_and_analysis.secret_scanning.status -ne "enabled" -or
  $repositoryState.security_and_analysis.secret_scanning_push_protection.status -ne "enabled"
)
if ($repositoryDrift -and $PSCmdlet.ShouldProcess($Repository, "merge 및 보안 설정 갱신")) {
  $null = Invoke-GhApi -Endpoint "/repos/$Repository" -Method PATCH -Body $desiredRepository
}

$actionsState = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions"
if (
  -not $actionsState.enabled -or
  $actionsState.allowed_actions -ne "selected" -or
  -not $actionsState.sha_pinning_required
) {
  if ($PSCmdlet.ShouldProcess($Repository, "Actions를 selected + full SHA 정책으로 갱신")) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions" -Method PUT -Body @{
        enabled = $true
        allowed_actions = "selected"
        sha_pinning_required = $true
      }
  }
}

if (-not $WhatIfPreference) {
  $selectedActions = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions/selected-actions"
  $selectedDrift = (
    -not $selectedActions.github_owned_allowed -or
    $selectedActions.verified_allowed -or
    -not (Test-StringSetEqual -Left @($selectedActions.patterns_allowed) -Right $AllowedActionPatterns)
  )
  if ($selectedDrift -and $PSCmdlet.ShouldProcess($Repository, "허용 외부 Action 목록 갱신")) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions/selected-actions" -Method PUT -Body @{
        github_owned_allowed = $true
        verified_allowed = $false
        patterns_allowed = $AllowedActionPatterns
      }
  }
}

$workflowPermission = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions/workflow"
if (
  $workflowPermission.default_workflow_permissions -ne "read" -or
  $workflowPermission.can_approve_pull_request_reviews
) {
  if ($PSCmdlet.ShouldProcess($Repository, "GITHUB_TOKEN 기본 권한을 read-only로 갱신")) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/actions/permissions/workflow" -Method PUT -Body @{
        default_workflow_permissions = "read"
        can_approve_pull_request_reviews = $false
      }
  }
}

$privateReporting = Invoke-GhApi -Endpoint "/repos/$Repository/private-vulnerability-reporting"
if (-not $privateReporting.enabled) {
  if ($PSCmdlet.ShouldProcess($Repository, "private vulnerability reporting 활성화")) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/private-vulnerability-reporting" -Method PUT
  }
}

if ($RulesetEnforcement -eq "Active" -and $null -eq $StatusCheckIntegrationId) {
  $StatusCheckIntegrationId = Find-StatusCheckIntegrationId -Contexts $RequiredStatusChecks
}

$approvalCount = if ($Mode -eq "Team") { 1 } else { 0 }
$teamMode = $Mode -eq "Team"
$statusCheckRules = @()
foreach ($context in $RequiredStatusChecks) {
  $item = [ordered]@{ context = $context }
  if ($null -ne $StatusCheckIntegrationId) {
    $item.integration_id = [int] $StatusCheckIntegrationId
  }
  $statusCheckRules += $item
}

$rulesetBody = [ordered]@{
  name = $rulesetName
  target = "branch"
  enforcement = $RulesetEnforcement.ToLowerInvariant()
  bypass_actors = @()
  conditions = [ordered]@{
    ref_name = [ordered]@{
      include = @("~DEFAULT_BRANCH")
      exclude = @()
    }
  }
  rules = @(
    @{ type = "deletion" },
    @{ type = "non_fast_forward" },
    @{ type = "required_linear_history" },
    [ordered]@{
      type = "pull_request"
      parameters = [ordered]@{
        allowed_merge_methods = @("squash")
        dismiss_stale_reviews_on_push = $teamMode
        require_code_owner_review = $teamMode
        require_last_push_approval = $false
        required_approving_review_count = $approvalCount
        required_review_thread_resolution = $true
      }
    },
    [ordered]@{
      type = "required_status_checks"
      parameters = [ordered]@{
        do_not_enforce_on_create = $false
        strict_required_status_checks_policy = $true
        required_status_checks = $statusCheckRules
      }
    }
  )
}

$rulesets = @(
  Invoke-GhApi -Endpoint "/repos/$Repository/rulesets?includes_parents=false&targets=branch&per_page=100"
)
$matches = @(
  $rulesets | Where-Object {
    $_.name -eq $rulesetName -and $_.source_type -eq "Repository"
  }
)
if ($matches.Count -gt 1) {
  throw "동일한 repository ruleset '$rulesetName'이 둘 이상입니다. 수동 정리가 필요합니다."
}

$rulesetNeedsWrite = $true
if ($matches.Count -eq 1) {
  $currentRuleset = Invoke-GhApi -Endpoint "/repos/$Repository/rulesets/$($matches[0].id)"
  $currentPullRequest = $currentRuleset.rules | Where-Object { $_.type -eq "pull_request" }
  $currentStatus = $currentRuleset.rules | Where-Object { $_.type -eq "required_status_checks" }
  $currentContexts = @(
    $currentStatus.parameters.required_status_checks | ForEach-Object { $_.context }
  )
  $rulesetNeedsWrite = (
    $currentRuleset.enforcement -ne $rulesetBody.enforcement -or
    [int] $currentPullRequest.parameters.required_approving_review_count -ne $approvalCount -or
    [bool] $currentPullRequest.parameters.dismiss_stale_reviews_on_push -ne $teamMode -or
    [bool] $currentPullRequest.parameters.require_code_owner_review -ne $teamMode -or
    -not (Test-StringSetEqual -Left $currentContexts -Right $RequiredStatusChecks)
  )
}

if ($rulesetNeedsWrite -and $PSCmdlet.ShouldProcess($Repository, "$RulesetEnforcement main ruleset 적용")) {
  if ($matches.Count -eq 0) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/rulesets" -Method POST -Body $rulesetBody
  }
  else {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/rulesets/$($matches[0].id)" -Method PUT -Body $rulesetBody
  }
}

if ($legacyProtection -and $RemoveLegacyBranchProtection) {
  if ($RulesetEnforcement -ne "Active") {
    throw "legacy branch protection은 active ruleset과 성공 check가 준비된 뒤에만 제거할 수 있습니다."
  }
  if ($PSCmdlet.ShouldProcess($Repository, "legacy main branch protection 제거")) {
    $null = Invoke-GhApi -Endpoint "/repos/$Repository/branches/main/protection" -Method DELETE
  }
}

if (-not $WhatIfPreference) {
  $verifyParameters = @{
    Repository = $Repository
    Mode = $Mode
    ExpectedRulesetEnforcement = $RulesetEnforcement
    RequiredStatusChecks = $RequiredStatusChecks
    AllowedActionPatterns = $AllowedActionPatterns
    AllowLegacyBranchProtection = ($RulesetEnforcement -eq "Disabled")
  }
  & $verifyPath @verifyParameters
  if (-not $?) {
    throw "설정 후 검증에 실패했습니다."
  }
}
