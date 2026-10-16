# 실제 앱 1차 구현 검증 (2026-10-12)

## Geoapify integration accepted for web trial (2026-10-16 FINAL)

- Coordinator acceptance under D-025: specialist implementation, independent source reviews and actual browser evidence combined. This accepts web map/search/registration and prototype alignment, not iPhone arrival or deployment.
- Real service: ignored local JSON syntax repaired without printing/changing the key; geocoding and PNG tile both HTTP200. Shinjuku3-17-3 search returned Matsumotokiyoshi at35.6917065,139.7033723 plus other candidates; user confirms result/pin.
- Final mobile author checks: analyze clean,50 tests pass, keyed web build success. Root independently executed earlier49 tests/analyze/build before the final semantics fix; do not mislabel final50 as root rerun.
- Actual isolated Chrome: address search, selected place, Vpoint save/reload. Found and fixed positionless semantic map click saving northwest corner. ExcludeSemantics on map plus explicit camera-center selection preserves physical pointer onTap. Postfix browser center save/reload exactly35.6917065,139.7033723; +30px physical tap saved longitude139.70465976032716 matching projection. ID/name/radius150/Vpoint retained.
- Evidence: developer task8e834bf71dd046d5b272c5ef43fa669c progress/tool history contains actual postfix execution; final report98eb33865c5f40a3b4c45193e29f6207 recovered handoff after600s timeout. Existing .orchestra/runtime-browser-report.md is PRE-FIX evidence, not final success evidence.
- Independent final mobile static review653c0265544840369781c00c3820ebbb: scoped code acceptance, no blocking defect. Reviewer did not execute Flutter/browser. Earlier read-only execution restrictions are environment failures, not failed app tests.
- Design: prototype search/pin/apps/save and explicit demo/error states updated. UI fixed retained manual draft and consistent pin transform;320x568/390x844 Chrome back/reentry, keyboard Enter/Space, storage failure/retry, reload/edit/delete/unlink checks passed. HTML final static reviewdf1c9e3e8ea049098ed6b0a023578f21 accepted. Prototype policies differ from Flutter as documented in design REVIEW.md.
- Credential check: no real key found in tracked or nonignored files. Local key JSON and build/web/main.dart.js git-ignored. No commit, push, paid upgrade or deployment performed. Local preview http://127.0.0.1:8793 only; built client key is not a server-side secret.
- Remaining: macOS/iPhone build and real arrival/background/notification/launch, VoiceOver and full device accessibility, broader Japanese search quality/usage measurement. Do not claim these passed.
- Ownership returned to root; no active implementation assignment. User-facing result delivered by root. Resume latest handoff/current sections only.


## Geoapify trial integration result (2026-10-16)

- Implemented: real Geoapify raster map on overview/editor, explicit Japanese store/address search (Japan filter and nearby bias), name/address results, manual pin selection, app selection and existing atomic local save. New radius 150m; existing ID/radius retained. No monthly coordinate refresh.
- Config: apps/mobile/config/geoapify.local.json exists, blank and git-ignored. User must paste the key locally; no key was printed or committed. Example file is tracked. README includes --dart-define-from-file run/build commands.
- Verified: developer final flutter analyze clean and full 47 tests passed (including 6 tile lifecycle tests). Root reran earlier 41 tests successfully and final web build passed after tile changes (60.8s). git diff --check passed.
- Independent reviewer 5d29bb346e1440d0ad68d7e17a179904 approved static code scope after fixing duplicate submits, safe 403/429 guidance, legacy registration test, 304/cache, normal aborts, late retry errors and body/image decode errors. Reviewer did not independently execute tests.
- Remaining: user key entry, real Geoapify search/map/usage check, macOS/iPhone build and arrival notifications, device accessibility. No paid subscription, deployment or Git commit performed.
- Ownership: ui/developer returned edited files to root; reviewer read-only. Code ready for live-key verification, not live-service/iPhone completion.


## 결과 구분

| 영역 | 결과 | 남은 확인 |
| --- | --- | --- |
| Flutter 관리·권한 안내·저장 | 코드 작성, 정적 분석 이상 없음, 17개 테스트 통과 | iPhone 실제 화면·기기 저장소 |
| Flutter 웹 미리보기 | 빌드 성공, 실제 첫 실행 화면·건너뛰기 후 홈 진입 확인 | 웹 검증을 iOS 검증으로 간주하지 않음 |
| Swift 위치·도착 알림·앱 중계 | 코드 작성 및 독립 정적 검토, 발견 결함 수정 | macOS 컴파일, XCTest, iPhone 실제 동작 모두 미실행 |
| iOS 설정 | plist·개인정보 manifest·launch storyboard XML 형식 확인 | Xcode 빌드·서명·심사 검증 미실행 |

## 실제 실행한 검사

- `flutter analyze`: No issues found.
- `flutter test`: 17개 통과. 무료 한도/중복 앱 집계, 입력 검증, 앱 삭제 시 연결 해제, 직렬 저장, 저장 실패·손상 데이터 보존, 신규 앱+장소 원자적 저장, 채널 미지원·실행 실패·상태 변경 이벤트, 첫 실행 건너뛰기, 등록·편집·삭제·재로드, 권한 상태 갱신과 저장 경합을 검사했다.
- `flutter build web --no-web-resources-cdn`: 웹 빌드 성공. 기본 일본어 위젯과 Cupertino 아이콘 폰트 포함.
- 실제 Chrome 모바일 크기에서 첫 사용 화면 캡처와 건너뛰기 터치를 통해 홈 진입 확인. 관리 UI 테스트는 네이티브 위치 감지/알림 실행 검증이 아니다.
- XML/plist 파싱 및 `git diff --check` 오류 없음. LF/CRLF 알림은 별도 포맷 오류로 처리하지 않았다.

## 독립 검토 및 수정

- Orchestra reviewer: Swift 선언·채널 검토 `eeecad299f774e85b83defad6ca08ee0`, 감시·중계 검토 `e7c587dce4494bbb912d5895b78188e5`, 수정 검토 `c06f9200120847d99410a5604612e257`.
- 수정: 알림 추가 실패 시 동일 토큰/시도의 cooldown 복구, 재시작 후 기존 지역의 미확정 상태 재요청, 시계 역행 시 무기한 억제 방지, 권한/중계 실패/알림 오류의 Dart 갱신 이벤트.
- Native 작성자와 다른 Flutter 코드에 대한 developer 독립 검토 `b8d1ae6457584c23b77a6610db07eb8e`: 모델·저장·채널에서 확정 결함 없음.
- reviewer 등록 흐름·테스트 검토 `e30d05bbca0b4f03ba68000724b859c4`: 차단 결함 없음. 요청된 신규 앱 동시 등록 및 저장 실패 검사 보강.
- 마지막 저장 경합 검토 `63c819952a9744de9aa98dde2ea6f7f3`: 소스 수준 수정 타당, 확정 차단 결함 없음. 해당 변경 후 루트가 분석·17개 테스트·웹 빌드 통과를 확인했다. 검토자의 실행 결과로 주장하지 않는다.
- 작업자 셸 오류로 코드 원문을 Orchestra로 수령하고 총괄이 승인된 파일에 저장·수정·실행했다. 검토자는 제공된 실제 소스를 정적으로 검토했으며 직접 실행한 테스트가 없다. 총괄 실행 증거와 혼동하지 않는다.

## 제품 완료로 볼 수 없는 부분

- iOS 빌드·서명·실제 iPhone 위치 감지/권한/알림 탭/외부 앱 전환은 미검증. 네이티브 cooldown XCTest를 작성했지만 Windows에서 실행하지 않았다.
- Vポイント는 공식 페이지 및 AASA로 확인한 링크만 등록했다. 실제 설치·미설치 상태와 이동 화면은 실기기 검증 필요. 다른 3개 카탈로그 앱의 실행 링크는 아직 미지원이며 실패를 안내한다.
- 장소당 0개/복수 앱 연결은 자동 알림 비활성. 여러 앱 중 대상 선택 정책은 확정하지 않았다.
- 실제 지도검색·유료 구매·유료 장소 한도·Android 네이티브 연동·배포는 이번 범위 밖이다.
- 지역 진입 알림과 0.1~0.2초 중계 시간을 보장하지 않는다. 강제 종료·백그라운드 새로고침 제한·권한 철회·배터리 및 재시작 상황은 실제 기기에서 검증해야 한다.

재개 기준: `APP_FLOW.md` → `MOBILE_CONTRACT.md` 관련 절 → `apps/mobile/README.md`의 기기 검증 절. 전체 코드 재독은 하지 않는다.
