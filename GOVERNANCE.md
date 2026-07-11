# 거버넌스

## 현재 운영 모드: solo

저장소 소유자가 최종 결정을 내립니다. required review 수는 0이지만 모든 변경은
PR을 거치고, 대화가 해결되며, `CI / gate`가 통과해야 합니다. merge 방식은 squash만
사용하고 GitHub native auto-merge를 허용합니다.

## 팀 모드 전환

팀 모드는 소유자가 프로젝트 생성 시 명시적으로 선언할 때만 활성화합니다.

1. 프로젝트 maintainer 팀과 최소 2명의 참여자를 구성합니다.
2. maintainer에게 해당 저장소 Write 이상 권한을 부여합니다.
3. 저장소에 로컬 `.github/CODEOWNERS`를 추가합니다.
4. required approval을 1 이상으로 변경합니다.
5. code owner review와 새 push 시 기존 승인 무효화를 활성화합니다.
6. 강제 push와 보호 브랜치 삭제 금지를 유지합니다.
7. 시험 PR로 승인, CI와 auto-merge 흐름을 검증합니다.
8. 전환 일자와 승인 팀을 프로젝트 문서에 기록합니다.

solo 복귀도 소유자의 명시적 결정, 정책 변경 PR과 설정 재검증을 요구합니다.
