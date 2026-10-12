# POINT mobile

Flutter 3.32.7 / Dart + Swift, iOS 14+ first. POINT is a working display name; final Cash & Point/C&P naming remains undecided. Product flow: ../../docs/APP_FLOW.md. Interface/ownership: ../../docs/MOBILE_CONTRACT.md.

## Implemented source

- Japanese black/white/yellow Flutter management UI, first-use permission explanation and choice, place/app CRUD, serialized local persistence and corrupt-data protection.
- Free limits: two places and three unique catalog apps. Reusing an app at multiple places counts once. Place entry can also register selected apps in one save. No purchase or paid-limit bypass.
- Current-location capture or manual coordinates; real map/search integration is deferred. The location preview is a schematic, not a live map.
- Swift Core Location region monitoring with Always authorization; local arrival notifications; native configuration restored before Flutter starts. No continuous GPS tracking or installed-app enumeration.
- A notification tap opens POINT, validates the current place/app/revision, then opens the allowlisted target once when active. No fixed splash delay or extra confirmation for a valid target. Ordinary startup never replays an old tap.
- Invalid/missing links, denied permissions, corrupt storage and platform failures are visible errors. Management UI is shared; web is verified, Android build/runtime is unverified. Native arrival and external-app launching are explicitly unavailable on Android/web.

## Native details and limits

One-app places are eligible for monitoring; zero/multiple-app places are inactive until the multi-app notification policy is decided. Default radius150m, allowed100?1000m. Initial inside state does not notify. Exit rearms; real entry notifies once per visit with a ten-minute cooldown. Failed notification submission restores its previous cooldown only if the same configuration/attempt is still current. Backward clock changes do not extend the cooldown indefinitely. Existing monitored regions with unknown initial state request it again after restart.

Configuration and visits are stored in native UserDefaults for background events. Read-back validates the in-process value, not a guarantee against sudden power loss. Deletion/editing invalidates old notification tokens. Permission downgrade stops monitoring when the OS/app reports it. iOS controls delivery; Background App Refresh, force-quit, power and location conditions can prevent or delay events. Do not claim exact arrival timing or a guaranteed0.1?0.2s relay.

Location requests may return before the system permission sheet resolves. Native stateChanged callbacks and Flutter resume refresh update status; notifications use a separate permission request. Launch errors are persisted and delivered to Flutter. The privacy manifest declares app-private UserDefaults usage; final privacy/store disclosure still needs review against the release binary.

## Official launch-link evidence (2026-10-12)

- V Point candidate: https://tpoint-app.onelink.me/RxPQ/vulagz8y
- Source: https://web.tsite.jp/app/official/tpointappli/ (iPhone page variant).
- https://tpoint-app.onelink.me/.well-known/apple-app-site-association associates /RxPQ/* with229375QH6W.jp.co.ccc.TSITE.
- The native opener uses universalLinksOnly: true, never treats a browser/App Store fallback as successful app launch. Actual installed/uninstalled behavior and destination require iPhone verification; no claim of direct barcode-screen support.
- PayPay, Rakuten Pay and d Point may be registered but currently have no enabled launch link. Their launch requests return failure. PayPay top-up/coupon URLs were not substituted for a payment/home entry.

Catalog selection is not a guarantee of merchant acceptance. No external URL from notifications or user input is executed.

## Windows checks / preview

From this directory:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
python -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:8791 for management UI. This is Flutter web, not an iPhone simulator. Test fixtures are test-only; a fresh install has no invented places/apps.

## macOS / iPhone checks (not executed here)

On an already approved Mac/cloud Mac with Xcode, CocoaPods and Flutter:

```sh
flutter pub get
flutter build ios --simulator
flutter build ios --release --no-codesign
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showdestinations
```

Run RunnerTests using an available simulator destination. A native cooldown regression test is supplied. Unsigned build output cannot simply be installed on an iPhone; signing/provisioning and any TestFlight distribution require the separately approved account/setup. No cloud account, upload, payment or distribution was performed.

Device acceptance checklist:
- First-use purpose screen; deny/allow/Always upgrade/revoke; manual management still available.
- Outside -> inside, duplicates, exit/reentry, cooldown, clock rollback, restart with unknown initial state, notification submission failure.
- Cold/warm notification tap; deletion/edit while pending; unsupported/uninstalled target; V Point universal link and one-time relay; normal launch does not relay.
- Screen locked/background/OS termination/force-quit tested separately; battery and actual delivery timing recorded.
- Native/Flutter configuration consistency after failed sync; corruption preserved; no silent reset.

See ../../docs/MOBILE_REVIEW.md for the actual executed checks and remaining limitations. Source implementation is not iOS runtime certification.
