# Dacon Organization 공통 운영 저장소

이 저장소는 [Dacon-Organization](https://github.com/Dacon-Organization)의 공개 프로필,
거버넌스 문서, 재사용 가능한 GitHub Actions, 워크플로 템플릿과 저장소 정책을 관리합니다.

> 이 조직은 DACON 플랫폼의 공식 운영 조직이 아니라 대회 참가와 학습을 위한
> 개인 프로젝트 모음입니다.

## 제공 항목

| 영역 | 위치 | 적용 방식 |
| --- | --- | --- |
| 조직 공개 프로필 | `profile/README.md` | 조직 첫 화면에 자동 표시 |
| 기본 커뮤니티 문서 | 저장소 루트 및 `.github/` | 파일이 없는 공개 저장소에 자동 적용 |
| 재사용 워크플로 | `.github/workflows/reusable-*.yml` | 각 저장소 caller가 전체 commit SHA로 호출 |
| 시작 템플릿 | `workflow-templates/` | 새 저장소의 Actions 화면에서 선택 |
| 저장소 정책 | `scripts/`, `policies/` | 소유자가 명시적으로 실행하고 검증 |

`AGENTS.md`, `LICENSE`, `CODEOWNERS`, `dependabot.yml`은 하위 저장소에 자동으로
상속되지 않습니다. 프로젝트를 분리할 때 각각 복제하고 프로젝트 상황에 맞게
수정해야 합니다. 하위 저장소에 자체 Issue Template이 하나라도 있으면 중앙 기본
Issue Template도 사용되지 않습니다.

## 표준 흐름

```text
pull → 개인 브랜치 → commit → push → PR → CI → GitHub native auto-merge
```

현재는 solo 운영이므로 승인 수는 0이지만 `main` 직접 push는 허용하지 않습니다.
팀 전환은 저장소 소유자가 프로젝트 생성 시 명시하며, 그때 승인 1명 이상과
CODEOWNERS 정책을 활성화합니다. 자세한 내용은 [GOVERNANCE.md](GOVERNANCE.md)와
[CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

공통 CI의 비교 근거와 채택·보류 결정은
[CI/CD 벤치마크](docs/ci-benchmark.md)에 기록합니다.

## 라이선스와 데이터

이 저장소에서 직접 작성한 코드와 문서는 [MIT License](LICENSE)를 적용합니다.
대회 데이터, 모델, 이미지 등 제3자 자료는 MIT 대상이 아니며 원 출처의 이용 조건과
재배포 권리를 따릅니다. 자세한 원칙은 [NOTICE.md](NOTICE.md)를 참고하세요.
