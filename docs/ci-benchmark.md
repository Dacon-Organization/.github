# 공통 CI/CD 벤치마크와 설계 결정

2026-07-11 KST에 GitHub API, 공식 문서와 공개 저장소를 확인했습니다. Star 수는
생태계 채택의 한 지표로만 사용하고, 최근 유지보수, 공식성, 최소 권한, 공급망
안전성과 현재 Python 프로젝트 적합성을 함께 평가했습니다.

## 도구 비교

| 후보 | 확인 Star | 결정 |
| --- | ---: | --- |
| [astral-sh/uv](https://github.com/astral-sh/uv) | 87,328 | lock 기반 설치를 프로젝트별로 단계 도입 |
| [astral-sh/ruff](https://github.com/astral-sh/ruff) | 48,508 | Python lint·format 표준으로 채택 |
| [actions/starter-workflows](https://github.com/actions/starter-workflows) | 11,819 | 공식 구조를 참고해 얇은 caller로 재작성 |
| [Super-Linter](https://github.com/super-linter/super-linter) | 10,515 | 현재 Python 중심 저장소에는 무거워 기본값에서 제외 |
| [rhysd/actionlint](https://github.com/rhysd/actionlint) | 4,028 | Actions 의미 검증에 채택 |
| [github/codeql-action](https://github.com/github/codeql-action) | 1,580 | 코드 저장소 분리 단계에서 default setup 적용 |
| [dependency-review-action](https://github.com/actions/dependency-review-action) | 877 | PR 의존성 변경 gate로 채택 |
| [pre-commit/action](https://github.com/pre-commit/action) | 559 | maintenance-only 상태를 고려해 미채택 |

대규모 Python 저장소의 workflow도 비교했습니다.

| 저장소 | 확인 Star | 가져온 패턴 |
| --- | ---: | --- |
| [FastAPI](https://github.com/fastapi/fastapi) | 100,347 | SHA pin, 최소 권한, uv, matrix와 gate |
| [Transformers](https://github.com/huggingface/transformers) | 162,473 | PR caller와 보안 검증 분리 |
| [Streamlit](https://github.com/streamlit/streamlit) | 45,198 | concurrency, timeout과 실패 artifact |
| [Pydantic](https://github.com/pydantic/pydantic) | 28,244 | lint·test·build 책임 분리 |

Star는 확인 시점의 스냅샷이며 이후 바뀔 수 있습니다.

## 채택한 공통 구조

- 공개 중앙 `.github` 저장소에 reusable workflow를 둡니다.
- 각 프로젝트에는 전체 중앙 commit SHA를 가리키는 얇은 caller만 둡니다.
- 외부 Action도 전체 40자리 commit SHA와 사람이 읽는 버전 주석을 함께 사용합니다.
- 기본 토큰은 `contents: read`, checkout credential은 보존하지 않습니다.
- workflow-level path filter를 두지 않아 required check 교착을 막습니다.
- `if: always()`인 caller-local gate를 사용해 check 이름을 안정화합니다.
- PR마다 Python·문서, 제목·브랜치 정책과 dependency review를 분리합니다.
- 실패 로그만 짧게 artifact로 남기고 데이터셋·환경 파일은 업로드하지 않습니다.

중앙 자체 CI는 Actionlint 1.7.12 바이너리를 SHA-256으로 검증한 뒤 실행하고,
Zizmor 1.26.1로 template injection과 과도한 권한을 검사합니다. 외부 URL 검사는
일시 장애로 필수 CI가 흔들리지 않도록 문서 PR에서는 Lychee offline 모드만
사용합니다.

## 보류한 항목

- CodeQL은 실제 코드가 있는 프로젝트를 분리할 때 GitHub default setup으로 켭니다.
- `uv.lock`은 각 프로젝트 의존성을 정리한 뒤 전환합니다. 초기 caller는 기존
  `requirements.txt`를 지원합니다.
- release-please, merge queue와 배포 workflow는 릴리스·배포 대상이 확정된
  프로젝트에만 추가합니다.
- 팀 모드 승인, CODEOWNERS와 배포 환경 승인은 소유자가 팀 전환을 선언할 때
  활성화합니다.
