import Flutter
import UIKit
import UserNotifications
import PushKit
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CXProviderDelegate {

  private var pushChannel: FlutterMethodChannel?
  private var callChannel: FlutterMethodChannel?
  private var pendingToken: String?
  private var pendingVoipToken: String?
  private var permissionState: String = "unknown"
  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private var callController = CXCallController()
  private var pendingCallEvents: [[String: Any]] = []
  private let pendingCallEventsDefaultsKey = "calc2.pendingCallEvents.v1"
  private let pendingCallEventsMaxCount = 100
  private let callContextsDefaultsKey = "calc2.callContexts.v1"
  private let callContextsMaxCount = 200
  private var persistedCallContexts: [String: [String: String]] = [:]
  private var callIdByUuid: [UUID: String] = [:]
  private var uuidByCallId: [String: UUID] = [:]
  private var payloadByUuid: [UUID: [String: Any]] = [:]
  private var suppressedEndUuids: Set<UUID> = []
  private var recentlySuppressedEndAtByUuid: [UUID: Date] = [:]
  private var answeredAtByUuid: [UUID: Date] = [:]
  private let answerTerminalNoiseGraceSec: TimeInterval = 14
  private var recentCallIdByFallbackSignature: [String: (callId: String, seenAt: Date)] = [:]
  private let fallbackSignatureTtlSec: TimeInterval = 180

  // MARK: – Application lifecycle

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ① Register plugins with the main Flutter engine
    GeneratedPluginRegistrant.register(with: self)
    loadPersistedPendingCallEvents()
    loadPersistedCallContexts()

    // ② Set up notification center delegate BEFORE asking permission
    UNUserNotificationCenter.current().delegate = self

    // ③ Wire up push MethodChannel.
    //    `window` is valid here because we *removed* SceneDelegate.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "calc2/push",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(nil); return }
        switch call.method {
        case "requestPermission":
          self.requestPermissionAndRegister(application) { granted in result(granted) }
        case "getToken":
          result(self.pendingToken)
        case "getVoipToken":
          result(self.pendingVoipToken)
        case "getInitialCallEvents":
          result(self.drainPendingCallEvents())
        case "permissionState":
          self.currentPermissionState { state in
            self.permissionState = state
            result(state)
          }
        case "dismissCall":
          let args = call.arguments as? [String: Any]
          let callId = args?["callId"] as? String
          self.dismissCall(callId: callId)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      pushChannel = channel
      setupCallChannel(controller)
    } else {
      // SceneDelegate case: schedule channel setup after engine is ready
      NSLog("[calc2] window/controller not ready at launch – will retry via notification")
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(onFlutterReady),
        name: UIApplication.didBecomeActiveNotification,
        object: nil
      )
    }

    // ④ Auto-request APNs registration on launch
    requestPermissionAndRegister(application, nil)
    setupCallKit()
    setupPushKit()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Fallback: set up channel on first active if window was not ready at launch.
  @objc private func onFlutterReady() {
    NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    guard pushChannel == nil,
          let controller = window?.rootViewController as? FlutterViewController else { return }

    let channel = FlutterMethodChannel(name: "calc2/push", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "requestPermission":
        self.requestPermissionAndRegister(UIApplication.shared) { granted in result(granted) }
      case "getToken":
        result(self.pendingToken)
      case "getVoipToken":
        result(self.pendingVoipToken)
      case "getInitialCallEvents":
        result(self.drainPendingCallEvents())
      case "permissionState":
        self.currentPermissionState { state in self.permissionState = state; result(state) }
      case "dismissCall":
        let args = call.arguments as? [String: Any]
        let callId = args?["callId"] as? String
        self.dismissCall(callId: callId)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    pushChannel = channel
    setupCallChannel(controller)
    NSLog("[calc2] pushChannel set up via fallback")

    // Send the pending token if we already have one
    if let token = pendingToken {
      channel.invokeMethod("onToken", arguments: ["token": token, "platform": "ios"])
    }
    if let voipToken = pendingVoipToken {
      channel.invokeMethod("onVoipToken", arguments: ["token": voipToken, "platform": "ios_voip"])
    }
  }

  private func setupCallChannel(_ controller: FlutterViewController) {
    if callChannel != nil { return }
    let channel = FlutterMethodChannel(name: "calc2/calls", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getInitialCallEvents":
        result(self.drainPendingCallEvents())
      case "dismissCall":
        let args = call.arguments as? [String: Any]
        let callId = args?["callId"] as? String
        self.dismissCall(callId: callId)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    callChannel = channel
  }

  private func setupCallKit() {
    let config = CXProviderConfiguration(localizedName: "Калькулятор")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false
    let provider = CXProvider(configuration: config)
    provider.setDelegate(self, queue: nil)
    callProvider = provider
  }

  private func setupPushKit() {
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  private func drainPendingCallEvents() -> [[String: Any]] {
    let events = pendingCallEvents
    pendingCallEvents.removeAll()
    persistPendingCallEvents()
    return events
  }

  private func loadPersistedPendingCallEvents() {
    guard
      let raw = UserDefaults.standard.array(forKey: pendingCallEventsDefaultsKey) as? [[String: Any]]
    else {
      return
    }
    pendingCallEvents = raw
    if pendingCallEvents.count > pendingCallEventsMaxCount {
      pendingCallEvents.removeFirst(pendingCallEvents.count - pendingCallEventsMaxCount)
    }
  }

  private func persistPendingCallEvents() {
    if pendingCallEvents.isEmpty {
      UserDefaults.standard.removeObject(forKey: pendingCallEventsDefaultsKey)
      return
    }
    UserDefaults.standard.set(pendingCallEvents, forKey: pendingCallEventsDefaultsKey)
  }

  private func enqueuePendingCallEvent(_ event: [String: Any]) {
    pendingCallEvents.append(event)
    if pendingCallEvents.count > pendingCallEventsMaxCount {
      pendingCallEvents.removeFirst(pendingCallEvents.count - pendingCallEventsMaxCount)
    }
    persistPendingCallEvents()
  }

  private func normalizedCallContext(callId: String, payload: [String: Any]) -> [String: String] {
    let normalizedCallId = callId.trimmingCharacters(in: .whitespacesAndNewlines)
    let kindRaw = stringValue(payload["kind"]) ?? "audio"
    return [
      "callId": normalizedCallId,
      "chatId": stringValue(payload["chatId"]) ?? "",
      "kind": kindRaw.isEmpty ? "audio" : kindRaw,
      "callerId": stringValue(payload["callerId"]) ?? "",
      "callerName": stringValue(payload["callerName"]) ?? ""
    ]
  }

  private func loadPersistedCallContexts() {
    guard
      let raw = UserDefaults.standard.dictionary(forKey: callContextsDefaultsKey) as? [String: [String: String]]
    else {
      return
    }
    persistedCallContexts = raw
    if persistedCallContexts.count > callContextsMaxCount {
      let overflow = persistedCallContexts.count - callContextsMaxCount
      let ordered = persistedCallContexts.keys.sorted()
      for idx in 0..<overflow {
        persistedCallContexts.removeValue(forKey: ordered[idx])
      }
      persistCallContexts()
    }
    for (uuidRaw, ctx) in persistedCallContexts {
      guard let uuid = UUID(uuidString: uuidRaw) else { continue }
      let callId = (ctx["callId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if callId.isEmpty { continue }
      let payload: [String: Any] = [
        "callId": callId,
        "chatId": ctx["chatId"] ?? "",
        "kind": ctx["kind"] ?? "audio",
        "callerId": ctx["callerId"] ?? "",
        "callerName": ctx["callerName"] ?? ""
      ]
      callIdByUuid[uuid] = callId
      uuidByCallId[callId] = uuid
      payloadByUuid[uuid] = payload
    }
  }

  private func persistCallContexts() {
    if persistedCallContexts.isEmpty {
      UserDefaults.standard.removeObject(forKey: callContextsDefaultsKey)
      return
    }
    UserDefaults.standard.set(persistedCallContexts, forKey: callContextsDefaultsKey)
  }

  private func rememberCallContext(uuid: UUID, callId: String, payload: [String: Any]) {
    let normalizedCallId = callId.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedCallId.isEmpty { return }
    if let existingUuid = uuidByCallId[normalizedCallId], existingUuid != uuid {
      callIdByUuid.removeValue(forKey: existingUuid)
      payloadByUuid.removeValue(forKey: existingUuid)
      answeredAtByUuid.removeValue(forKey: existingUuid)
      persistedCallContexts.removeValue(forKey: existingUuid.uuidString)
    }
    callIdByUuid[uuid] = normalizedCallId
    uuidByCallId[normalizedCallId] = uuid
    var normalizedPayload = payload
    normalizedPayload["callId"] = normalizedCallId
    normalizedPayload["chatId"] = stringValue(payload["chatId"]) ?? ""
    normalizedPayload["kind"] = stringValue(payload["kind"]) ?? "audio"
    normalizedPayload["callerId"] = stringValue(payload["callerId"]) ?? ""
    normalizedPayload["callerName"] = stringValue(payload["callerName"]) ?? ""
    payloadByUuid[uuid] = normalizedPayload
    persistedCallContexts[uuid.uuidString] = normalizedCallContext(
      callId: normalizedCallId,
      payload: normalizedPayload
    )
    if persistedCallContexts.count > callContextsMaxCount {
      let overflow = persistedCallContexts.count - callContextsMaxCount
      let ordered = persistedCallContexts.keys.sorted()
      for idx in 0..<overflow {
        persistedCallContexts.removeValue(forKey: ordered[idx])
      }
    }
    persistCallContexts()
  }

  private func removeCallContext(uuid: UUID, fallbackCallId: String? = nil) {
    let removedCallId = callIdByUuid.removeValue(forKey: uuid) ??
      fallbackCallId?.trimmingCharacters(in: .whitespacesAndNewlines)
    payloadByUuid.removeValue(forKey: uuid)
    if let callId = removedCallId, let mappedUuid = uuidByCallId[callId], mappedUuid == uuid {
      uuidByCallId.removeValue(forKey: callId)
    }
    persistedCallContexts.removeValue(forKey: uuid.uuidString)
    if let callId = removedCallId, !callId.isEmpty {
      let staleKeys = persistedCallContexts
        .filter { (_, ctx) in (ctx["callId"] ?? "") == callId }
        .map { $0.key }
      for key in staleKeys {
        persistedCallContexts.removeValue(forKey: key)
      }
    }
    persistCallContexts()
  }

  private func pruneAnsweredNoiseMarkers(now: Date = Date()) {
    let cutoff = now.addingTimeInterval(-answerTerminalNoiseGraceSec)
    answeredAtByUuid = answeredAtByUuid.filter { _, ts in ts >= cutoff }
    recentlySuppressedEndAtByUuid = recentlySuppressedEndAtByUuid.filter { _, ts in ts >= cutoff }
  }

  private func resolveCallContext(uuid: UUID) -> (callId: String, payload: [String: Any]) {
    if let mappedCallId = callIdByUuid[uuid] {
      let payload = payloadByUuid[uuid] ?? [
        "callId": mappedCallId,
        "chatId": "",
        "kind": "audio",
        "callerId": "",
        "callerName": ""
      ]
      return (mappedCallId, payload)
    }
    if let stored = persistedCallContexts[uuid.uuidString] {
      let callId = (stored["callId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !callId.isEmpty {
        let payload: [String: Any] = [
          "callId": callId,
          "chatId": stored["chatId"] ?? "",
          "kind": stored["kind"] ?? "audio",
          "callerId": stored["callerId"] ?? "",
          "callerName": stored["callerName"] ?? ""
        ]
        rememberCallContext(uuid: uuid, callId: callId, payload: payload)
        return (callId, payload)
      }
    }
    let payload = payloadByUuid[uuid] ?? [:]
    let fallbackCallId = (payload["callId"] as? String) ?? uuid.uuidString
    return (fallbackCallId, payload)
  }

  private func emitCallEvent(_ event: [String: Any]) {
    var delivered = false
    // Prefer dedicated call channel. Duplicating the same event to both
    // channels can create repeated incoming/decline handling in Flutter.
    if let channel = callChannel {
      channel.invokeMethod("onCallEvent", arguments: event)
      delivered = true
    } else if let channel = pushChannel {
      channel.invokeMethod("onCallEvent", arguments: event)
      delivered = true
    }
    // Buffer only before Flutter channels are ready.
    // Re-buffering every live event causes stale replay on next launch.
    if !delivered {
      enqueuePendingCallEvent(event)
    }
  }

  private func stringValue(_ value: Any?) -> String? {
    if let s = value as? String {
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
  }

  private func dictionaryValue(_ value: Any?) -> [String: Any] {
    if let map = value as? [String: Any] {
      return map
    }
    if let map = value as? [AnyHashable: Any] {
      var out: [String: Any] = [:]
      for (key, item) in map {
        if let k = key as? String {
          out[k] = item
        }
      }
      return out
    }
    if let raw = value as? String,
       let rawData = raw.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
      return parsed
    }
    return [:]
  }

  private func fallbackSignature(
    chatId: String,
    callerId: String,
    callerName: String,
    kind: String
  ) -> String? {
    let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
    if !chatId.isEmpty && !callerId.isEmpty {
      return "chat:\(chatId)|caller:\(callerId)|kind:\(normalizedKind)"
    }
    let normalizedName = callerName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if !normalizedName.isEmpty {
      return "name:\(normalizedName)|kind:\(normalizedKind)"
    }
    return nil
  }

  private func pruneRecentFallbackCallIds(now: Date) {
    recentCallIdByFallbackSignature = recentCallIdByFallbackSignature.filter { _, item in
      now.timeIntervalSince(item.seenAt) <= fallbackSignatureTtlSec
    }
    if recentCallIdByFallbackSignature.count > 400 {
      let sorted = recentCallIdByFallbackSignature.sorted { lhs, rhs in
        lhs.value.seenAt < rhs.value.seenAt
      }
      let overflow = recentCallIdByFallbackSignature.count - 300
      for idx in 0..<overflow {
        recentCallIdByFallbackSignature.removeValue(forKey: sorted[idx].key)
      }
    }
  }

  private func rememberRecentFallbackCallId(callId: String, signature: String?) {
    guard let signature = signature, !signature.isEmpty else { return }
    let now = Date()
    recentCallIdByFallbackSignature[signature] = (callId: callId, seenAt: now)
    pruneRecentFallbackCallIds(now: now)
  }

  private func resolveRecentFallbackCallId(signature: String?) -> String? {
    guard let signature = signature, !signature.isEmpty else { return nil }
    let now = Date()
    pruneRecentFallbackCallIds(now: now)
    return recentCallIdByFallbackSignature[signature]?.callId
  }

  private func callPayload(from dictionary: [AnyHashable: Any]) -> [String: Any] {
    var raw: [String: Any] = [:]
    for (key, value) in dictionary {
      if let k = key as? String { raw[k] = value }
    }
    let data = dictionaryValue(raw["data"])
    let aps = dictionaryValue(raw["aps"])
    let alert = dictionaryValue(aps["alert"])
    func pick(_ keys: [String]) -> String? {
      for k in keys {
        if let v =
          stringValue(raw[k]) ??
          stringValue(data[k]) ??
          stringValue(aps[k]) ??
          stringValue(alert[k]) {
          return v
        }
      }
      return nil
    }

    let chatId = pick(["chatId", "chat_id"]) ?? ""
    let kind = pick(["kind", "mediaType"]) ?? "audio"
    let callerId = pick(["callerId", "fromUserId", "from"]) ?? ""
    let callerName = pick(["callerName", "fromUserName", "name"]) ?? "Входящий вызов"
    let signature = fallbackSignature(chatId: chatId, callerId: callerId, callerName: callerName, kind: kind)
    let callId: String
    if let parsedCallId = pick(["callId", "call_id"]) {
      callId = parsedCallId
      rememberRecentFallbackCallId(callId: callId, signature: signature)
    } else if !chatId.isEmpty && !callerId.isEmpty {
      callId = "sig:\(chatId)|\(callerId)|\(kind)"
      rememberRecentFallbackCallId(callId: callId, signature: signature)
    } else if let cachedCallId = resolveRecentFallbackCallId(signature: signature) {
      callId = cachedCallId
    } else {
      callId = UUID().uuidString
      NSLog("[calc2] call payload without callId/chatId/callerId; fallback UUID=%@", callId)
    }

    return [
      "type": "call:incoming",
      "action": "incoming",
      "callId": callId,
      "chatId": chatId,
      "kind": kind,
      "callerId": callerId,
      "callerName": callerName
    ]
  }

  private func reportIncomingCall(_ payload: [String: Any], completion: (() -> Void)? = nil) {
    let callId = (payload["callId"] as? String) ?? UUID().uuidString
    let uuid = UUID(uuidString: callId) ?? UUID()
    if let existing = uuidByCallId[callId] {
      // Duplicate push for the same callId (voip + alert race or resend).
      // Keep a single CallKit call to prevent double incoming UI.
      rememberCallContext(uuid: existing, callId: callId, payload: payload)
      emitCallEvent(payload)
      completion?()
      return
    }
    rememberCallContext(uuid: uuid, callId: callId, payload: payload)

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: (payload["callerName"] as? String) ?? "Входящий вызов")
    update.hasVideo = (payload["kind"] as? String) == "video"
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false

    callProvider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error = error {
        NSLog("[calc2] report incoming call failed: %@", error.localizedDescription)
        self?.removeCallContext(uuid: uuid, fallbackCallId: callId)
      } else {
        self?.emitCallEvent(payload)
      }
      completion?()
    }
  }

  private func dismissCall(callId: String?) {
    guard let callId = callId, !callId.isEmpty else { return }
    var targetUuid = uuidByCallId[callId]
    if targetUuid == nil {
      targetUuid = persistedCallContexts.first(where: { (_, ctx) in
        (ctx["callId"] ?? "") == callId
      }).flatMap { UUID(uuidString: $0.key) }
    }
    guard let uuid = targetUuid else { return }
    suppressedEndUuids.insert(uuid)
    let end = CXEndCallAction(call: uuid)
    let tx = CXTransaction(action: end)
    callController.request(tx) { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        self.suppressedEndUuids.remove(uuid)
        NSLog("[calc2] dismiss call failed: %@", error.localizedDescription)
      }
    }
  }

  // MARK: – Permission helpers

  private func currentPermissionState(completion: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let state: String
      switch settings.authorizationStatus {
      case .authorized, .ephemeral, .provisional: state = "granted"
      case .denied: state = "denied"
      case .notDetermined: state = "notDetermined"
      @unknown default: state = "unknown"
      }
      DispatchQueue.main.async { completion(state) }
    }
  }

  private func requestPermissionAndRegister(
    _ application: UIApplication,
    _ completion: ((Bool) -> Void)?
  ) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { [weak self] settings in
      guard let self = self else { return }
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        self.permissionState = "granted"
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
          completion?(true)
        }
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
          guard let self = self else { return }
          self.permissionState = granted ? "granted" : "denied"
          if let error = error {
            NSLog("[calc2] requestAuthorization error: %@", error.localizedDescription)
          }
          if granted {
            DispatchQueue.main.async {
              application.registerForRemoteNotifications()
            }
          }
          DispatchQueue.main.async { completion?(granted) }
        }
      case .denied:
        self.permissionState = "denied"
        DispatchQueue.main.async { completion?(false) }
      @unknown default:
        DispatchQueue.main.async { completion?(false) }
      }
    }
  }

  // MARK: – APNs callbacks

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    pendingToken = token
    NSLog("[calc2] APNs token: %@…", String(token.prefix(12)))
    pushChannel?.invokeMethod("onToken", arguments: ["token": token, "platform": "ios"])
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[calc2] APNs registration failed: %@", error.localizedDescription)
    pushChannel?.invokeMethod("onRegistrationError", arguments: ["error": error.localizedDescription])
  }

  // MARK: – Foreground notifications

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .badge, .sound])
  }

  // MARK: – PushKit

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
    pendingVoipToken = token
    NSLog("[calc2] VoIP token: %@…", String(token.prefix(12)))
    pushChannel?.invokeMethod("onVoipToken", arguments: ["token": token, "platform": "ios_voip"])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    if type == .voIP { pendingVoipToken = nil }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let call = callPayload(from: payload.dictionaryPayload)
    reportIncomingCall(call, completion: completion)
  }

  // MARK: – CallKit

  func providerDidReset(_ provider: CXProvider) {
    callIdByUuid.removeAll()
    uuidByCallId.removeAll()
    payloadByUuid.removeAll()
    suppressedEndUuids.removeAll()
    recentlySuppressedEndAtByUuid.removeAll()
    answeredAtByUuid.removeAll()
    persistedCallContexts.removeAll()
    persistCallContexts()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let context = resolveCallContext(uuid: action.callUUID)
    let payload = context.payload
    let callId = context.callId
    pruneAnsweredNoiseMarkers()
    rememberCallContext(uuid: action.callUUID, callId: callId, payload: payload)
    answeredAtByUuid[action.callUUID] = Date()
    emitCallEvent([
      "action": "answer",
      "type": "call:answer",
      "callId": callId,
      "chatId": payload["chatId"] ?? "",
      "kind": payload["kind"] ?? "audio",
      "callerId": payload["callerId"] ?? "",
      "callerName": payload["callerName"] ?? ""
    ])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let context = resolveCallContext(uuid: action.callUUID)
    let payload = context.payload
    let callId = context.callId
    let now = Date()
    pruneAnsweredNoiseMarkers(now: now)
    let isSuppressed = suppressedEndUuids.remove(action.callUUID) != nil
    let answeredAt = answeredAtByUuid[action.callUUID]
    let suppressedAt = recentlySuppressedEndAtByUuid[action.callUUID]
    let isRepeatedSuppressedNoise =
      suppressedAt != nil &&
      now.timeIntervalSince(suppressedAt!) <= answerTerminalNoiseGraceSec
    let isPostAnswerNoise =
      answeredAt != nil &&
      now.timeIntervalSince(answeredAt!) <= answerTerminalNoiseGraceSec
    if isSuppressed || isPostAnswerNoise {
      recentlySuppressedEndAtByUuid[action.callUUID] = now
    }
    if !isSuppressed && !isPostAnswerNoise && !isRepeatedSuppressedNoise {
      emitCallEvent([
        "action": "decline",
        "type": "call:decline",
        "callId": callId,
        "chatId": payload["chatId"] ?? "",
        "kind": payload["kind"] ?? "audio",
        "callerId": payload["callerId"] ?? "",
        "callerName": payload["callerName"] ?? ""
      ])
    } else if isPostAnswerNoise {
      NSLog("[calc2] suppress CallKit end immediately after answer callId=%@", callId)
    } else if isRepeatedSuppressedNoise {
      NSLog("[calc2] suppress repeated CallKit end noise callId=%@", callId)
    }
    removeCallContext(uuid: action.callUUID, fallbackCallId: callId)
    action.fulfill()
  }
}
