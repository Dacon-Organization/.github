# 저장소 정책

`main-protection.solo.json`과 `main-protection.team.json`은 검토용 기준 문서입니다.
bootstrap 교착을 막기 위해 `enforcement`는 `disabled`이며 check integration ID도
하드코딩하지 않습니다.

적용 순서는 다음과 같습니다.

1. caller workflow를 개인 브랜치에 push하고 시험 PR을 생성합니다.
2. `scripts/configure-repository.ps1 -RulesetEnforcement Disabled`로 기본 설정과
   비활성 ruleset을 준비합니다.
3. 세 gate가 성공한 뒤 같은 스크립트를 `-RulesetEnforcement Active`로 실행합니다.
   스크립트가 최근 성공 check에서 GitHub Actions app ID를 찾습니다.
4. `scripts/verify-repository.ps1`로 최종 상태를 읽기 전용 검증합니다.

기존 legacy branch protection이 있으면 active ruleset과 누적됩니다. 스크립트는
기본적으로 중단하며, 새 CI와 active ruleset을 확인한 뒤에만
`-RemoveLegacyBranchProtection`을 명시적으로 사용합니다.
