# 앱 흐름 및 구현 기준

> FINAL 2026-10-16: Geoapify web trial accepted by coordinator after specialist fixes, actual search/map/save/reload/coordinate checks,50 tests and independent static reviews. Local API key configured and Git-excluded. Earlier pending-key and pre-fix statements below are historical. iPhone arrival remains unverified. See PROJECT_STATUS latest result.

> 2026-10-16 implementation result: map/search/manual-pin code and local key configuration are ready. Analysis + 47 tests + web build passed; independent static review approved. Real API verification awaits local key entry; iPhone arrival remains unverified. See PROJECT_STATUS.md and apps/mobile/README.md.

> CURRENT 2026-10-16 / D-024: User approved Geoapify free-plan map/search implementation and has created an API key. This supersedes older candidate-only / unimplemented descriptions below. Store-name search falls back to address search and manual pin placement. Preserve local coordinates without monthly renewal. Paid upgrades and deployment are excluded. Implementation and real API/iPhone validation statuses are tracked separately in PROJECT_STATUS.md.


기록일: 2026-10-12. 사용자 요청과 문서 저장 계획 승인에 따른 기준 문서. 최신 구현 승인: D-021, 세부 계약: `docs/MOBILE_CONTRACT.md`.
관련 기능 코드를 작성하거나 검토하기 전에 해당 절을 반드시 확인한다. 최신 사용자 지시가 우선하며 변경 시 이 문서와 결정·인계를 함께 갱신한다.

지도·장소 검색 구현 전에는 [지도 사용 방향](MAP_EVALUATION.md)의 **최신 사용 방향 — 다음 구현의 필수 기준**을 먼저 읽는다. Geoapify는 우선 검증 후보이며 최종 채택은 미확정이다. 매달 앱 실행·장소 재등록을 요구하지 않는 흐름을 지킨다.

## 1. 목적과 현재 상태

- 일본 거주 사용자가 계산대에서 본인의 결제·포인트 앱을 빠르게 찾도록 돕는다. iPhone/iOS 우선, 첫 표시 언어는 일본어다. Android는 후속 대상이며 동시 출시는 확정하지 않았다.
- 앱은 최초 설정과 장소·앱 추가/수정 때 열어 관리한다. 일상적으로 계속 열어 보는 대시보드를 전제로 하지 않는다.
- 검정·흰색·노랑 디자인, 하단 메뉴와 등록·수정·삭제·브라우저 저장은 HTML 시안에서 구현·검증했다. 시안 위치: `docs/design/point-home/`, 검증 기록: `docs/design/point-home/REVIEW.md`.
- `apps/mobile`에 Flutter 관리·권한 안내·저장 코드와 Swift 위치 감지·로컬 도착 알림·앱 중계 실행 코드를 작성했다. Windows Flutter 검증과 iOS 실제 동작 검증을 구분한다. macOS 빌드·iPhone 실기기 검증은 미실행이다.
- 실제 지도·장소 검색은 아직 미구현이다. 현재 코드의 위치 취득·좌표 입력 화면은 지도·검색 목록 방식으로 교체할 대상이며 최종 UX가 아니다. 외부 앱은 Vポイント 공식 링크만 활성화했고 실제 기기 실행은 미검증이다. PayPay·楽天ペイ·dポイント 실행 링크와 여러 앱 알림 정책은 후속이다.

## 2. 첫 실행과 사용자 선택

- 첫 사용 과정에서 위치와 알림을 왜 사용하는지 먼저 설명한다. 사용자가 허용 여부를 선택할 수 있어야 한다.
- 실제 권한은 운영체제의 위치·알림 권한 요청으로 받는다. 자체 안내 화면에서 동의했다고 시스템 권한을 얻은 것으로 취급하지 않는다.
- 거절 시 자동 도착 안내가 제한됨을 설명하고 수동 등록·관리는 가능하게 한다. 백그라운드 위치 권한의 단계·요청 시점은 기술 검증 후 결정한다.
- 권한 동의 또는 우리 앱 경유만으로 스토어 심사 통과가 보장된다고 주장하지 않는다.

## 3. 장소와 앱 등록

- 지도 → 매장명·주소 검색 → 지점 목록 → 선택·핀 확인 → 포인트·결제 앱 연결 → 등록으로 구성한다. 좌표를 직접 입력하게 하지 않는다. 검색에 없는 장소는 지도에서 직접 지정할 수 있게 한다.
- 사용자가 장소와 안내받을 결제·포인트 앱을 직접 선택해 연결한다.
- 휴대폰에 설치된 앱 전체를 조회·수집하거나 다른 앱 내부 데이터를 들여다보는 방식으로 구현하지 않는다.
- 등록된 연결은 사용자 선택이며, 해당 매장에서 그 앱을 실제 사용할 수 있다는 보증이나 공식 가맹점 데이터로 취급하지 않는다.

## 4. 도착 알림과 앱 실행

1. 허용된 위치 권한 범위에서 등록 장소 도착을 감지한다.
2. 그 장소에 사용자가 연결한 앱을 안내하는 알림을 표시한다.
3. 사용자가 알림을 터치하면 우리 앱이 열린다.
4. 우리 앱이 해당 알림의 등록 장소·대상 앱을 확인한다.
5. 대상 앱이 지원하는 실행 링크로 결제·포인트 앱을 연다.

- 사용자가 알림을 누르기 전 도착 이벤트만으로 외부 앱을 자동 실행하지 않는다.
- 알림에서 외부 앱으로 직접 이동하지 않고 반드시 우리 앱을 경유한다. 대상이 정해진 경우 불필요한 추가 터치나 인위적 대기 없이 전환하는 것이 목표다.
- 사용자는 우리 앱이 약 0.1~0.2초만 보이는 빠른 전환을 희망한다. 이는 고정 시간 보장이 아니며 OS·기기·앱 시작 상태와 지원 링크에 따라 실기기로 검증해야 한다.
- 앱 미설치·지원 링크 없음·실행 실패 시 우리 앱에 머물며 실패 사유와 가능한 다음 행동을 안내한다. 성공하지 않은 실행을 성공으로 표시하지 않는다.

## 5. 미결정 및 후속 검증

- Flutter + Dart와 Swift iOS 연결로 구현 승인. 무료 장소2·서로 다른 앱3; 일회성 구매 방향이지만 실제 구매·유료한도는 후속. 구현 기본값은 `docs/MOBILE_CONTRACT.md` 참조.
- 실제 장소 데이터 출처와 지도·검색 연동 방식.
- 1차 구현은 로컬 도착 알림을 사용한다. 서버 푸시/APNs 연동은 포함하지 않는다.
- 장소에 여러 앱을 연결했을 때 알림 구성과 실행 대상 선택 방식. 임의로 한 앱을 자동 선택하지 않는다.
- 앱별 공식 실행 링크 지원, 링크로 열 수 있는 화면 및 실패 처리. 임의 링크를 검증된 것으로 기록하지 않는다.
- 권한 허용·거절·철회, 백그라운드·종료·재시작, 알림 터치 후 중계 실행, 배터리 영향을 실제 iPhone에서 검증한다.
- Cash & Point/C&P 최종 명칭은 검토 중이다. 클라우드 가입·과금·배포·스토어 등록 승인은 별도다.

## 6. 작업 재개

- Orchestra 최신 인계 → 이 문서의 관련 절 → 담당 변경 파일 순서로 확인한다. 누락·충돌이 없는 한 전체 코드와 과거 기록을 반복해서 읽지 않는다.
- 총괄이 본 문서·상태·결정을 갱신한다. 전문 구현·독립 검토는 Orchestra로 배정하고 인계에 이 문서 경로를 포함한다.
