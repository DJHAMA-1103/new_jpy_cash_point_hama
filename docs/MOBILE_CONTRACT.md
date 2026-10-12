# Flutter / iOS implementation contract (2026-10-12)

Approved scope: docs/APP_FLOW.md plus D-021. Native iOS first; Android/web must explicitly report native arrival/launch unavailable, never simulate success. No payments, accounts, tracking SDKs, installed-app enumeration or server integration.

## Ownership
- UI Orchestra role: apps/mobile/lib/**, pubspec.yaml, pubspec.lock, test/**, assets/**. Flutter UI, models, persistence, tests.
- developer Orchestra role: apps/mobile/ios/** and apps/mobile/README.md. Swift implementation, native settings, test instructions. Do not edit Dart files.
- root: scaffold, project status/decisions/flow and this contract; integration fixes only after handoff.
- reviewer: read-only independent review/test.

## Native channel `jp.cashandpoint/native`
All method args/results JSON-compatible. Errors use FlutterError(code,message,details). Flutter catches and displays failures, preserving local data.
- `status` -> {location: notDetermined|denied|restricted|whenInUse|always, notifications: notDetermined|denied|authorized|provisional, monitoringAvailable: bool, monitoredCount: int, lastError: string|null}.
- `requestWhenInUse`, `requestAlways` -> same status map (requestAlways only from whenInUse, not automatic startup). Request notification permission separately via `requestNotifications` -> status map.
- `currentLocation` -> {latitude: double, longitude: double}; single reading with timeout/error, not continuous tracking.
- `syncConfiguration` args {apps:[string IDs], places:[{id:string,name:string,latitude:double,longitude:double,radius:double,appIds:[string]}]} -> status map. Persist native mirror for background entry/launch before Flutter is ready. Enforce free limit 2 places, 3 unique catalog app IDs and schema validation on both sides. IDs stable. Radius default 150m, permitted 100..1000m; coordinates valid finite ranges. Reject invalid snapshot without replacing saved mirror.
- `openApp` args {appId:string} -> bool; only allowlisted officially supported links, false/error never browser fallback that masquerades as app success.
- `consumeLaunchError` -> string|null; one-shot error from native notification handling, for Flutter to show after ready/resume.
- `openSettings` -> bool; app's own system settings only.
- Native-to-Dart `stateChanged` event (no payload): refresh actual status/consume launch error, queue if already busy; no automatic permission requests. iOS deployment minimum14.0.

Fixed catalog IDs: paypay, rakuten_pay, v_point, d_point. UI may register them, but no invented URLs. v_point official candidate https://tpoint-app.onelink.me/RxPQ/vulagz8y (official V-point page and AASA confirmed 2026-10-12); real-device launch unverified. Other launch targets unavailable pending official links. Native README records evidence. Swift validates app IDs and uses its own allowlist, never accepts a URL in a notification payload. Unknown/unsupported targets give honest failure. Catalog names are not proof of merchant acceptance.

## Lifecycle / scope defaults
- Swift handles notification tap natively after app becomes active; payload has placeId/appId, revalidated against latest mirror. Clear pending tap before launch to avoid repeat on resume. No waiting for Flutter or fixed 0.2s timer. No external launch on arrival alone.
- Monitor only authorizedAlways + notifications allowed + valid places with exactly one linked app. Multi-app mappings can be saved/edited but explicitly display that automatic notification is pending selection-policy decision; never silently select first or fan out notifications. Unlinked places inactive.
- Notify on true entry once per visit, rearm on exit, persist entry state, suppress same-place duplicates for 10 minutes. Do not generate arrival notification merely from initial inside status at registration. Reconcile deletion/edits and clear stale notifications; permission downgrade disables monitoring. Region delivery timing/force-quit limitations documented, not promised.
- Flutter startup loads real local state (no fake registered samples), no artificial splash delay. Show first-use purpose/choice before requests; users can skip. Later direct opens are management only. Onboarding completion persists. App settings exposes actual permission state and retry/settings actions.
- Free limits apply to total registered app catalog IDs, not per-place links; deleting app unlinks it. No paid flag or fake purchase bypass. Limits explain future one-time expansion is not yet sold.
- Place entry initially name + current-location capture or manual coordinates; actual map/place search deferred and not faked. Preserve accepted black/white/yellow layout and bottom places/add/apps nav; map area can show registered-location schematic explicitly, not a real map.
- Use simple Flutter SDK state and shared_preferences for local persistence. Flutter SDK localizations provide Japanese system widget text; cupertino_icons supplies the iOS icon font required by Flutter widgets. No unrelated packages. Save serialized mutations, report storage failure, no silent overwrite on corrupt JSON. Tests cover free limits, invalid inputs, persistence failure/corruption, deletion links, native channel unavailable, onboarding/navigation.

Native compile/device validation requires macOS/Xcode/signing; Windows tests are not evidence of iOS runtime success. Cloud subscription/upload/distribution not authorized.
