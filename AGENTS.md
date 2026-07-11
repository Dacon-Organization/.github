# Dacon Organization Agent 운영 규칙

이 파일은 이 중앙 저장소에 직접 적용됩니다. 하위 프로젝트에는 자동 상속되지
않으므로 프로젝트 분리 시 루트에 복제하고 필요한 세부 규칙을 추가합니다.

## 필수 작업 흐름

1. `main`을 pull하여 최신 상태를 확인합니다.
2. `feature|fix|docs|refactor|test|chore|ci/<github-id>-<description>` 형식의 개인
   브랜치를 만듭니다.
3. 한 작업만 수행하고 관련 검증을 실행합니다.
4. 의미 있는 파일만 stage하고 한국어 커밋 메시지를 작성합니다.
5. 브랜치를 push하고 PR을 만듭니다.
6. 필수 CI가 통과하면 GitHub native auto-merge를 사용합니다.
7. 한 작업이 끝나면 결과와 다음 작업을 보고하고 멈춥니다.

`main` 직접 push와 강제 push는 금지합니다. 현재 solo 모드에서는 required review가
0이지만 PR, CI, 소유자의 최종 diff 확인은 생략하지 않습니다.

## 이름 규칙

- 브랜치 예: `feature/kik32-python-ci`
- 커밋 예: `✨ Feat: Python 공통 CI 추가`
- PR 예: `[ci] Python 공통 CI 추가`
- 커밋 prefix: `✨ Feat`, `🐛 Fix`, `📝 Docs`, `🎨 Style`, `♻️ Refactor`,
  `✅ Test`, `🔧 Chore`

## 품질과 보안

- 대화, 문서, 주석, 커밋과 PR은 한국어로 작성합니다.
- 들여쓰기는 2 spaces를 사용합니다.
- 외부 GitHub Action은 전체 40자리 commit SHA로 고정하고 버전 주석을 남깁니다.
- 워크플로 권한은 기본 `contents: read`로 두고 필요한 job에만 추가합니다.
- `pull_request_target`은 별도 위협 모델과 승인 없이는 사용하지 않습니다.
- 비밀정보, 개인정보와 인증 토큰을 저장소나 CI 로그에 기록하지 않습니다.
- 제3자 데이터는 출처, 이용 조건과 재배포 권리를 확인하고 문서화합니다.
- 공통 필수 check는 최종 `CI / gate`를 사용합니다. 내부 정책 check는
  `PR Policy / gate`, `Dependency Review / gate`입니다.

Claude Code를 사용하는 프로젝트는 `CLAUDE.md`에서 `@AGENTS.md`를 import합니다.
