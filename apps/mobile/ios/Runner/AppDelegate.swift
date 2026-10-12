import Flutter
import UIKit
import CoreLocation
import UserNotifications
import CoreFoundation

private let pointCategory = "POINT_ARRIVAL"

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var native: PointNative!
    private var channel: FlutterMethodChannel?

    override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        native = PointNative()
        GeneratedPluginRegistrant.register(with: self)
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        UNUserNotificationCenter.current().delegate = self
        attachChannel()
        native.refreshMonitoring()
        return result
    }

    private func attachChannel() {
        guard channel == nil, let controller = window?.rootViewController as? FlutterViewController else { return }
        let bridge = FlutterMethodChannel(name: "jp.cashandpoint/native", binaryMessenger: controller.binaryMessenger)
        bridge.setMethodCallHandler { [weak self] call, result in
            DispatchQueue.main.async {
                guard let native = self?.native else {
                    result(FlutterError(code: "unavailable", message: "ネイティブ機能を利用できません。", details: nil))
                    return
                }
                native.handle(call, result: result)
            }
        }
        channel = bridge
        native.onStateChanged = { [weak self] in
            self?.channel?.invokeMethod("stateChanged", arguments: nil)
        }
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        attachChannel()
        native?.refreshMonitoring()
        native?.relayPendingTap()
    }

    override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.content.categoryIdentifier == pointCategory else {
            super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
            return
        }
        let info = response.notification.request.content.userInfo
        let isDefault = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        DispatchQueue.main.async { [weak self] in
            if isDefault { self?.native?.acceptTap(info) }
            completionHandler()
        }
    }

    override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard notification.request.content.categoryIdentifier == pointCategory else {
            super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard self?.native?.validPayload(notification.request.content.userInfo) == true else {
                completionHandler([])
                return
            }
            completionHandler([.alert, .sound])
        }
    }
}

private struct PointPlace: Codable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let appIds: [String]
}

private struct PointConfiguration: Codable {
    let apps: [String]
    let places: [PointPlace]
}

private struct PointVisit: Codable {
    var inside: Bool?
    var lastNotification: TimeInterval?
}

private struct PointStore: Codable {
    var version: Int = 1
    var configuration: PointConfiguration
    var tokens: [String: String]
    var visits: [String: PointVisit]
}

private struct PointTap {
    let placeId: String
    let appId: String
    let token: String
}

private enum PointValidation: Error {
    case invalid(String)
}

enum PointArrivalPolicy {
    static func isCoolingDown(last: TimeInterval?, now: TimeInterval) -> Bool {
        guard let last = last else { return false }
        return now >= last && now - last < 600
    }
}

private final class PointNative: NSObject, CLLocationManagerDelegate {
    var onStateChanged: (() -> Void)?
    private static let catalog: Set<String> = ["paypay", "rakuten_pay", "v_point", "d_point"]
    private static let appNames = ["paypay": "PayPay", "rakuten_pay": "楽天ペイ", "v_point": "Vポイント", "d_point": "dポイント"]
    // Official V-point page + its published AASA association, checked 2026-10-12.
    // Device opening still needs verification. No browser/App Store fallback.
    private static let launchLinks: [String: URL] = [
        "v_point": URL(string: "https://tpoint-app.onelink.me/RxPQ/vulagz8y")!
    ]
    private let defaults = UserDefaults.standard
    private let storageKey = "jp.cashandpoint.native.snapshot.v1"
    private let launchErrorKey = "jp.cashandpoint.native.launchError"
    private let prefix = "point.region."
    private let manager = CLLocationManager()
    private let notifications = UNUserNotificationCenter.current()
    private var store = PointStore(configuration: PointConfiguration(apps: [], places: []), tokens: [:], visits: [:])
    private var storageBlocked = false
    private var lastError: String?
    private var refreshGeneration = 0
    private var pendingTap: PointTap?
    private var locationResult: FlutterResult?
    private var locationTimeout: DispatchWorkItem?
    private var locationStarted: Date?

    override init() {
        super.init()
        loadStore()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    private var authorization: CLAuthorizationStatus {
        if #available(iOS 14.0, *) { return manager.authorizationStatus }
        return CLLocationManager.authorizationStatus()
    }

    private var locationLabel: String {
        switch authorization {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default: return "restricted"
        }
    }

    private func notificationLabel(_ settings: UNNotificationSettings) -> String {
        switch settings.authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "authorized"
        @unknown default: return "denied"
        }
    }

    private func notificationsAllowed(_ settings: UNNotificationSettings) -> Bool {
        let label = notificationLabel(settings)
        return label == "authorized" || label == "provisional"
    }

    private var hardwareAvailable: Bool {
        CLLocationManager.locationServicesEnabled() && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }

    private func fail(_ result: FlutterResult, _ code: String, _ message: String) {
        lastError = message
        result(FlutterError(code: code, message: message, details: nil))
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "status":
            refreshMonitoring(result)
        case "requestWhenInUse":
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            refreshMonitoring(result)
        case "requestAlways":
            guard authorization == .authorizedWhenInUse else {
                if authorization == .authorizedAlways { refreshMonitoring(result) }
                else { fail(result, "permission_order", "先に「アプリの使用中」の位置情報を許可してください。") }
                return
            }
            manager.requestAlwaysAuthorization()
            refreshMonitoring(result)
        case "requestNotifications":
            notifications.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self = self else {
                        result(FlutterError(code: "unavailable", message: "通知機能を利用できません。", details: nil))
                        return
                    }
                    if let error = error { self.lastError = error.localizedDescription }
                    self.refreshMonitoring(result)
                }
            }
        case "currentLocation":
            readLocation(result)
        case "syncConfiguration":
            guard !storageBlocked else {
                fail(result, "storage_corrupt", "保存データを読み込めません。データを上書きせず停止しました。")
                return
            }
            do {
                let configuration = try Self.validate(call.arguments)
                var next = store
                next.configuration = configuration
                next.tokens = [:]
                next.visits = [:]
                for place in configuration.places {
                    let previous = store.configuration.places.first { $0.id == place.id }
                    if previous == place, let token = store.tokens[place.id] {
                        next.tokens[place.id] = token
                        next.visits[place.id] = store.visits[place.id] ?? PointVisit()
                    } else {
                        next.tokens[place.id] = UUID().uuidString
                        next.visits[place.id] = PointVisit(inside: nil, lastNotification: store.visits[place.id]?.lastNotification)
                    }
                }
                guard save(next) else {
                    fail(result, "storage_failed", "設定を保存できませんでした。")
                    return
                }
                refreshMonitoring(result)
            } catch {
                let message: String
                if case PointValidation.invalid(let reason) = error { message = reason }
                else { message = "設定の形式が正しくありません。" }
                fail(result, "invalid_configuration", message)
            }
        case "openApp":
            guard let args = call.arguments as? [String: Any], let id = args["appId"] as? String, Self.catalog.contains(id) else {
                fail(result, "invalid_app", "未対応のアプリIDです。")
                return
            }
            launch(id) { success in result(success) }
        case "consumeLaunchError":
            let error = defaults.string(forKey: launchErrorKey)
            defaults.removeObject(forKey: launchErrorKey)
            result(error)
        case "openSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.applicationState == .active else { result(false); return }
            UIApplication.shared.open(url, options: [:]) { success in result(success) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let double = value.doubleValue
        return double.isFinite ? double : nil
    }

    private static func validate(_ raw: Any?) throws -> PointConfiguration {
        guard let args = raw as? [String: Any], let apps = args["apps"] as? [String], let rows = args["places"] as? [[String: Any]], apps.count <= 3, rows.count <= 2, Set(apps).count == apps.count, Set(apps).isSubset(of: catalog) else {
            throw PointValidation.invalid("登録上限または設定の形式が正しくありません。")
        }
        var ids = Set<String>()
        var places: [PointPlace] = []
        for row in rows {
            guard let id = row["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 200, ids.insert(id).inserted,
                  let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
                  let lat = number(row["latitude"]), (-90...90).contains(lat),
                  let lon = number(row["longitude"]), (-180...180).contains(lon),
                  let linked = row["appIds"] as? [String], Set(linked).count == linked.count, Set(linked).isSubset(of: Set(apps)) else {
                throw PointValidation.invalid("場所のID・名前・座標・アプリ設定を確認してください。")
            }
            let radius: Double
            if row["radius"] == nil { radius = 150 }
            else if let value = number(row["radius"]) { radius = value }
            else { throw PointValidation.invalid("半径は数値で指定してください。") }
            guard (100...1000).contains(radius) else { throw PointValidation.invalid("半径は100〜1000mで指定してください。") }
            places.append(PointPlace(id: id, name: name, latitude: lat, longitude: lon, radius: radius, appIds: linked))
        }
        return PointConfiguration(apps: apps, places: places)
    }

    private func loadStore() {
        guard defaults.object(forKey: storageKey) != nil else { return }
        do {
            guard let data = defaults.data(forKey: storageKey) else { throw PointValidation.invalid("storage") }
            let decoded = try JSONDecoder().decode(PointStore.self, from: data)
            let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded.configuration))
            _ = try Self.validate(raw)
            let ids = Set(decoded.configuration.places.map { $0.id })
            guard decoded.version == 1, Set(decoded.tokens.keys) == ids, Set(decoded.visits.keys) == ids, Set(decoded.tokens.values).count == ids.count, decoded.tokens.values.allSatisfy({ UUID(uuidString: $0) != nil }), decoded.visits.values.allSatisfy({ $0.lastNotification == nil || ($0.lastNotification!.isFinite && $0.lastNotification! >= 0) }) else { throw PointValidation.invalid("storage") }
            store = decoded
        } catch {
            storageBlocked = true
            lastError = "保存データが破損しています。上書きせず監視を停止しました。"
        }
    }

    @discardableResult private func save(_ next: PointStore) -> Bool {
        guard !storageBlocked else { return false }
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: storageKey)
            guard defaults.data(forKey: storageKey) == data else {
                lastError = "保存データの確認に失敗しました。"
                return false
            }
            store = next
            return true
        } catch {
            lastError = "保存データの変換に失敗しました。"
            return false
        }
    }

    func refreshMonitoring(_ result: FlutterResult? = nil) {
        refreshGeneration += 1
        let generation = refreshGeneration
        notifications.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else {
                    result?(FlutterError(code: "unavailable", message: "状態を取得できません。", details: nil))
                    return
                }
                if generation == self.refreshGeneration { self.reconcile(settings) }
                result?([
                    "location": self.locationLabel,
                    "notifications": self.notificationLabel(settings),
                    "monitoringAvailable": self.hardwareAvailable,
                    "monitoredCount": self.manager.monitoredRegions.filter { $0.identifier.hasPrefix(self.prefix) }.count,
                    "lastError": self.lastError.map { $0 as Any } ?? NSNull()
                ])
            }
        }
    }

    private func regionID(_ place: PointPlace) -> String { prefix + (store.tokens[place.id] ?? "invalid") }

    private func placeForRegion(_ region: CLRegion) -> PointPlace? {
        store.configuration.places.first { regionID($0) == region.identifier && $0.appIds.count == 1 }
    }

    private func reconcile(_ settings: UNNotificationSettings) {
        let enabled = !storageBlocked && hardwareAvailable && authorization == .authorizedAlways && notificationsAllowed(settings)
        let places = enabled ? store.configuration.places.filter { $0.appIds.count == 1 } : []
        let desired = Set(places.map { regionID($0) })
        var next = store
        var changed = false
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) && !desired.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        // Disabled or ambiguous mappings must establish a new initial state when resumed.
        for place in store.configuration.places where !desired.contains(regionID(place)) {
            if next.visits[place.id]?.inside != nil {
                next.visits[place.id]?.inside = nil
                changed = true
            }
        }
        if changed { _ = save(next) }
        let existing = Set(manager.monitoredRegions.map { $0.identifier })
        for region in manager.monitoredRegions {
            if let place = placeForRegion(region), desired.contains(region.identifier), store.visits[place.id]?.inside == nil {
                manager.requestState(for: region)
            }
        }
        for place in places where !existing.contains(regionID(place)) {
            let maxRadius = manager.maximumRegionMonitoringDistance
            guard maxRadius > 0, place.radius <= maxRadius else {
                lastError = "この端末では指定した半径の場所を監視できません。"
                continue
            }
            var initial = store
            initial.visits[place.id]?.inside = nil
            guard save(initial) else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), radius: place.radius, identifier: regionID(place))
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        pruneNotifications()
    }

    private func pruneNotifications() {
        notifications.getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let stale = requests.filter { $0.identifier.hasPrefix(self.prefix) && !self.validPayload($0.content.userInfo) }.map { $0.identifier }
                self.notifications.removePendingNotificationRequests(withIdentifiers: stale)
            }
        }
        notifications.getDeliveredNotifications { [weak self] delivered in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let stale = delivered.filter { $0.request.identifier.hasPrefix(self.prefix) && !self.validPayload($0.request.content.userInfo) }.map { $0.request.identifier }
                self.notifications.removeDeliveredNotifications(withIdentifiers: stale)
            }
        }
    }

    private func tap(_ info: [AnyHashable: Any]) -> PointTap? {
        guard let place = info["placeId"] as? String, let app = info["appId"] as? String, let token = info["token"] as? String else { return nil }
        return PointTap(placeId: place, appId: app, token: token)
    }

    private func valid(_ tap: PointTap) -> Bool {
        guard !storageBlocked, store.tokens[tap.placeId] == tap.token, Self.catalog.contains(tap.appId), store.configuration.apps.contains(tap.appId), let place = store.configuration.places.first(where: { $0.id == tap.placeId }) else { return false }
        return place.appIds == [tap.appId]
    }

    func validPayload(_ info: [AnyHashable: Any]) -> Bool {
        guard let payload = tap(info) else { return false }
        return valid(payload)
    }

    func acceptTap(_ info: [AnyHashable: Any]) {
        guard let payload = tap(info), valid(payload) else {
            pendingTap = nil
            recordLaunchError("通知の登録内容が変更されています。場所とアプリを確認してください。")
            return
        }
        pendingTap = payload
        relayPendingTap()
    }

    func relayPendingTap() {
        guard UIApplication.shared.applicationState == .active, let payload = pendingTap else { return }
        pendingTap = nil
        guard valid(payload) else {
            recordLaunchError("通知の登録内容が変更されています。")
            return
        }
        launch(payload.appId) { [weak self] success in
            if !success { self?.recordLaunchError("このアプリの起動リンクは未対応、または起動できませんでした。アプリを手動で開いてください。") }
        }
    }

    private func recordLaunchError(_ message: String) {
        lastError = message
        defaults.set(message, forKey: launchErrorKey)
        onStateChanged?()
    }

    private func launch(_ id: String, completion: @escaping (Bool) -> Void) {
        guard Self.catalog.contains(id), store.configuration.apps.contains(id), UIApplication.shared.applicationState == .active, let url = Self.launchLinks[id], let scheme = url.scheme?.lowercased(), scheme != "http" else {
            lastError = "登録済みアプリの公式起動リンクを利用できません。手動で開いてください。"
            completion(false)
            return
        }
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = scheme == "https" ? [.universalLinksOnly: true] : [:]
        UIApplication.shared.open(url, options: options) { [weak self] success in
            DispatchQueue.main.async {
                if !success { self?.lastError = "対象アプリを開けませんでした。" }
                completion(success)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard placeForRegion(region) != nil else {
            if region.identifier.hasPrefix(prefix) { manager.stopMonitoring(for: region) }
            return
        }
        manager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard authorization == .authorizedAlways, let place = placeForRegion(region), store.visits[place.id]?.inside == nil, state != .unknown else { return }
        var next = store
        next.visits[place.id]?.inside = state == .inside
        _ = save(next)
        // Initial state NEVER creates an arrival notification.
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard !storageBlocked, authorization == .authorizedAlways, let place = placeForRegion(region), let token = store.tokens[place.id] else { return }
        let previous = store.visits[place.id] ?? PointVisit()
        guard previous.inside != true else { return }
        var next = store
        next.visits[place.id]?.inside = true
        guard save(next), previous.inside == false else { return }
        let app = place.appIds[0]
        let payload = PointTap(placeId: place.id, appId: app, token: token)
        notifications.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self, self.authorization == .authorizedAlways, self.notificationsAllowed(settings), self.valid(payload), self.store.visits[place.id]?.inside == true else { return }
                let now = Date().timeIntervalSince1970
                let previousNotification = self.store.visits[place.id]?.lastNotification
                if PointArrivalPolicy.isCoolingDown(last: previousNotification, now: now) { return }
                var updated = self.store
                updated.visits[place.id]?.lastNotification = now
                guard self.save(updated) else { return }
                let content = UNMutableNotificationContent()
                content.title = "登録した場所の近くです"
                content.body = "\(place.name)：\(Self.appNames[app] ?? app)を開きます。未対応の場合はPOINTでご案内します。"
                content.categoryIdentifier = pointCategory
                content.sound = .default
                content.userInfo = ["placeId": place.id, "appId": app, "token": token]
                let requestID = self.prefix + token
                let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
                self.notifications.add(request) { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let error = error {
                            self.lastError = error.localizedDescription
                            if self.store.tokens[place.id] == token, self.store.visits[place.id]?.lastNotification == now {
                                var restored = self.store
                                restored.visits[place.id]?.lastNotification = previousNotification
                                _ = self.save(restored)
                            }
                            self.onStateChanged?()
                        }
                        if !self.valid(payload) || self.authorization != .authorizedAlways || self.store.visits[place.id]?.inside != true {
                            self.notifications.removePendingNotificationRequests(withIdentifiers: [requestID])
                            self.notifications.removeDeliveredNotifications(withIdentifiers: [requestID])
                        }
                    }
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let place = placeForRegion(region) else { return }
        var next = store
        next.visits[place.id]?.inside = false
        _ = save(next)
        notifications.removePendingNotificationRequests(withIdentifiers: [region.identifier])
        notifications.removeDeliveredNotifications(withIdentifiers: [region.identifier])
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        lastError = "場所の監視に失敗しました：" + error.localizedDescription
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationChanged() }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { authorizationChanged() }

    private func authorizationChanged() {
        if authorization == .denied || authorization == .restricted {
            finishLocation(error: FlutterError(code: "location_denied", message: "位置情報が許可されていません。", details: nil))
        }
        refreshMonitoring()
        onStateChanged?()
    }

    private func readLocation(_ result: @escaping FlutterResult) {
        guard locationResult == nil else { fail(result, "location_busy", "位置情報を取得中です。"); return }
        guard CLLocationManager.locationServicesEnabled(), authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            fail(result, "location_denied", "位置情報を許可してから再試行してください。")
            return
        }
        locationResult = result
        locationStarted = Date()
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishLocation(error: FlutterError(code: "location_timeout", message: "位置情報の取得がタイムアウトしました。再試行または座標を入力してください。", details: nil))
        }
        locationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationResult != nil, let started = locationStarted, let location = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.timestamp >= started.addingTimeInterval(-5) && abs($0.timestamp.timeIntervalSinceNow) <= 30 && CLLocationCoordinate2DIsValid($0.coordinate) }) else { return }
        let result = locationResult
        locationResult = nil
        locationStarted = nil
        locationTimeout?.cancel()
        locationTimeout = nil
        result?(["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
        finishLocation(error: FlutterError(code: "location_failed", message: "位置情報を取得できませんでした。", details: error.localizedDescription))
    }

    private func finishLocation(error: FlutterError) {
        guard let result = locationResult else { return }
        locationResult = nil
        locationStarted = nil
        locationTimeout?.cancel()
        locationTimeout = nil
        lastError = error.message
        result(error)
    }
}
