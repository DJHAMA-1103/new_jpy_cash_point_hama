# 홈 시안 검토 (2026-10-10)

- 범위: 기존 검정·흰색·노랑 디자인 유지, 하단 등록 장소/＋등록/내 앱 메뉴, HTML 시안 상호작용.
- 구현: design_recovery. index.html, style.css, app.js. node --check 통과.
- 독립 코드 검토: home_feasibility. 탭 분기·선택상태·접근성 라벨·키보드 이동·삭제 연결 정합성 확인. 모바일 토스트 위치 우선순위 문제 발견 후 UI 담당 수정.
- 독립 브라우저 검증: overall_coordinator. Chrome CDP 실제 클릭으로 메뉴 전환, 장소/앱 등록, 새로고침 저장 유지, 편집/뒤로, 장소 삭제, 앱 삭제와 연결 해제·장소 보존, 설정 복귀 확인.
- 위치정보 오프는 첫 복합 자동클릭에서 검증 실패. 별도 재검증에서 현재지점 숨김·수동등록 안내·장소선택 진입 통과. 최초 실패 원인은 확정하지 않음.
- 화면: app-home.png, 390×844 CSS 픽셀, 배율 2. 하단 메뉴 고정과 목록 영역 분리 확인.
- 수정 재검증: reload 후 모바일 토스트 computed bottom=98px 확인. 자체검사 7개 통과. 독립 검토 결과와 화면을 총괄 취합하여 HTML 시안 범위 완료.
- 미검증: 실제 iPhone, 실제 위치 감지·알림·외부 앱 실행. 이번 결과는 HTML 프로토타입이며 제품 앱 출시 검증이 아님.

## Geoapify flow design alignment (2026-10-16)

- Author: Orchestra ui. Assigned files only: index.html, style.css, app.js, REVIEW.md. Ownership returned to root after this handoff; independent review pending.
- Preserved Japanese black/white/yellow, bottom tabs and browser CRUD. Explicit demo search now precedes shared name/pin confirmation, app selection and final atomic local save. Existing-place editing keeps its ID; back navigation preserves name/pin/app draft. No coordinates are entered by users.
- Honest prototype: fixed fictional places and map; no API/key access, live search, OS permission request or arrival claim. Flutter is identified as the real-search implementation. State preview covers missing configuration, connection failure, empty results, denied location, tile failure and usage restriction. These are labeled display examples, not provider responses. Missing configuration hides candidates and disables manual registration within the preview.
- Accessibility source changes: status regions, visible search label, Enter/Space pin button, 44px close/location controls, 16px inputs, wrapping actions and candidate text, visible focus, short-screen adjustment. Existing heading focus and modal behavior retained.
- Executed: node --check; git diff --check; Node VM with DOM stubs: existing 7 state validation cases, demo/empty search, four unavailable-result states, denied-location search fallback, pin name and app draft retention, failed-storage atomicity, successful place+app save and duplicate-save guard. All passed. DOM stubs do not establish actual browser interaction, layout or screen-reader behavior.
- Browser validation attempted twice through cua; both failed during initialization (trusted Node process exited unexpectedly). No installed local playwright/puppeteer/@playwright/test package found. Screenshot not regenerated; app-home.png remains the 2026-10-10 artifact and is not evidence for these changes.
- Required independent acceptance: 320x568 and 390x844 layouts plus large text; keyboard search/select/pin/apps/back/save; persistence after reload; rename/edit/delete and app unlink; storage-failure recovery; VoiceOver status announcements; all state previews. Real iPhone/API/arrival validation belongs to Flutter and was not run here.
- Deliberate prototype limits: pin adjustment switches between two fictional positions; displayed areas are fictional, not geocoded street addresses; final confirmation is retained as an extra design step. No dependencies or external services added.


## Pin draft review fixes and browser regression (2026-10-16)

- Author: Orchestra ui; changed only app.js and REVIEW.md. Ownership returned to root for independent final review. index.html/style.css and existing screenshots are unchanged.
- Fixed: returning to the same manual draft preserves its name and coordinates both before and after app selection. Switching from a sample candidate to manual starts a new name/pin; selecting a different candidate resets its name/pin. Selecting the same candidate retains its draft. Both initial rendering and pin adjustment now use renderDraftPin(), so (68,65) always renders translate(36px,15px).
- Executed with installed Playwright and headless Chrome, fresh isolated contexts at 320x568 and 390x844: manual pin/back/re-entry before and after app selection; matching marker transforms; candidate/manual reset; Enter/Space activation; app selection retention; six labeled state previews; injected Storage.setItem failure leaves place/app counts and persisted state unchanged; retry succeeds; reload retains name, coordinates and linked app; rename, place deletion, app deletion/unlink with place preserved; close restores opener focus; zero pageerror events. Both viewport runs passed (exit 0).
- Layout checks: home and search dialog have no horizontal overflow at both sizes; search dialog with all text scaled to 150% has no horizontal overflow and manual-add action remains scroll-reachable. This is automated browser geometry/visibility evidence, not screenshot visual approval, OS Dynamic Type, or full large-text coverage of every step.
- Existing .orchestra/prototype-runtime.cjs also passed (exit 0), executed in memory using its installed Playwright module and a fresh Chrome launch; report/screenshot writes were removed to respect assigned ownership. Existing artifacts were not overwritten. New regression assertions were executed via Node stdin without additional workspace files. node --check app.js and scoped git diff --check passed.
- Initial new browser check failed because PowerShell converted a Japanese assertion literal to question marks. Replaced the test literal with Unicode escapes; complete rerun passed. No application failure was observed in that attempt.
- Prototype/Flutter policy difference (reviewer handoff): HTML starts with 3 places/4 apps, validates up to 100 places/6 apps and requires at least one app when submitting. Flutter free limits are 2 places/3 apps and permit saving without an app. These pre-existing demo policies were not changed; the HTML is not proof of Flutter limit or validation parity. Extra final confirmation and two-position fictional pin behavior also remain intentional demo differences.
- Not run: iPhone, VoiceOver, real API/arrival, full keyboard tab-order audit, screenshot visual review, or all-step large-text accessibility. No credentials or mobile/backend source accessed; no permissions or root records changed. Independent acceptance remains with root/reviewer.
