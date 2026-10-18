import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Kove Navigation Dashboard Protocol Constants & Helpers

/// Text sanitizer that strips non-ASCII diacritics / unicode characters to prevent
/// motorcycle TFT display firmware rendering bugs or crashes.
/// Matches Android `t0.java` normalization.
struct KoveTextSanitizer {
    static let customReplacements: [(String, String)] = [
        ("ł", "l"), ("Ł", "L"),
        ("ß", "ss"),
        ("ø", "o"), ("Ø", "O"),
        ("æ", "ae"), ("Æ", "AE"),
        ("œ", "oe"), ("Œ", "OE"),
        ("đ", "d"), ("Đ", "D"),
        ("ı", "i"),
        ("þ", "th"), ("Þ", "Th")
    ]
    
    static func sanitize(_ text: String, maxLength: Int = 40) -> String {
        var str = text
        for (orig, repl) in customReplacements {
            str = str.replacingOccurrences(of: orig, with: repl)
        }
        
        // Decompose unicode characters into base glyphs + combining diacritics
        let decomposed = str.folding(options: .diacriticInsensitive, locale: .current)
        
        // Strip non-ASCII combining marks and non-printable characters
        let asciiChars = decomposed.unicodeScalars.filter { scalar in
            scalar.isASCII && scalar.value >= 32 && scalar.value <= 126
        }
        
        let cleaned = String(String.UnicodeScalarView(asciiChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength))
        }
        return cleaned
    }
}

/// Kove / ThinkerRide TFT Navigation Icon Enumeration
enum KoveNaviIcon: Int {
    case inactive = 0
    case turnLeft = 2
    case turnRight = 3
    case slightLeft = 4
    case slightRight = 5
    case sharpLeft = 6
    case sharpRight = 7
    case uTurn = 8
    case straight = 9
    case roundaboutGeneric = 12
    case arrived = 21
    case arrivedLeft = 22
    case arrivedRight = 23
    
    // Roundabout exits 1..12
    case roundaboutExit1 = 31
    case roundaboutExit2 = 32
    case roundaboutExit3 = 33
    case roundaboutExit4 = 34
    case roundaboutExit5 = 35
    case roundaboutExit6 = 36
    case roundaboutExit7 = 37
    case roundaboutExit8 = 38
    case roundaboutExit9 = 39
    case roundaboutExit10 = 40
    case roundaboutExit11 = 41
    case roundaboutExit12 = 42
    
    case forkRight = 43
    case forkLeft = 44
    case rampLeft = 45
    case rampRight = 46
}

// MARK: - NavigationSyncManager

class NavigationSyncManager: ObservableObject {
    static let shared = NavigationSyncManager()
    
    weak var bleController: BleController?
    
    // Active Navigation State
    private var activeRoute: MKRoute?
    private var destinationName: String = ""
    private var currentStepIndex: Int = 0
    private var distanceToNextStepMeters: CLLocationDistance = 0
    private var distanceRemainingMeters: CLLocationDistance = 0
    private var timeRemainingSeconds: TimeInterval = 0
    private var lastUserSpeedKmH: Int = 0
    
    private var isNavigating: Bool = false
    private var hasArrived: Bool = false
    private var arrivalTickCount: Int = 0
    
    // Timer & Throttling
    private var syncTimer: Timer?
    private var tickCounter: Int = 0
    private var lastSentSignature: String = ""
    private var lastDestinationSentTime: Date = Date.distantPast
    
    private init() {}
    
    // MARK: - Lifecycle & BLE Controller Binding
    
    func startSync(bleController: BleController) {
        self.bleController = bleController
        bleController.log("🧭 Navigation Sync Manager connected to BLE.")
        
        // If navigation is already running on the phone when BLE connects, restore it immediately
        if isNavigating {
            resendCurrentState()
        }
    }
    
    func stopSync() {
        bleController?.log("🧭 Navigation Sync Manager disconnected from BLE.")
        self.bleController = nil
    }
    
    // MARK: - Navigation Session Tracking
    
    func startNavigation(route: MKRoute, destination: MKMapItem) {
        self.activeRoute = route
        self.destinationName = destination.name ?? "Destination"
        self.currentStepIndex = 0
        self.distanceRemainingMeters = route.distance
        self.timeRemainingSeconds = route.expectedTravelTime
        self.isNavigating = true
        self.hasArrived = false
        self.arrivalTickCount = 0
        self.tickCounter = 0
        self.lastSentSignature = ""
        
        if let firstStep = route.steps.first {
            self.distanceToNextStepMeters = firstStep.distance
        }
        
        bleController?.log("🧭 Navigation started to '\(destinationName)' (\(Int(route.distance))m)")
        
        // 1. Send initial destination packet (act 1)
        sendDestinationPacket(destinationName)
        
        // 2. Send initial maneuver update (act 3)
        sendManeuverUpdate()
        
        // 3. Start 1-second update timer loop matching Android m1.java & l1.java
        startTimer()
    }
    
    func stopNavigation() {
        guard isNavigating || hasArrived else { return }
        
        bleController?.log("🧭 Navigation stopped. Sending end navigation packet (msg_id 15)...")
        isNavigating = false
        hasArrived = false
        activeRoute = nil
        destinationName = ""
        currentStepIndex = 0
        lastSentSignature = ""
        
        stopTimer()
        
        // Send end navigation packet to dashboard
        bleController?.sendNavigationEnd()
    }
    
    func updateProgress(
        stepIndex: Int,
        distanceToStep: CLLocationDistance,
        totalRemainingDistance: CLLocationDistance,
        timeRemaining: TimeInterval,
        speedKmH: Int
    ) {
        guard isNavigating else { return }
        
        self.currentStepIndex = stepIndex
        self.distanceToNextStepMeters = distanceToStep
        self.distanceRemainingMeters = totalRemainingDistance
        self.timeRemainingSeconds = timeRemaining
        self.lastUserSpeedKmH = speedKmH
    }
    
    func triggerArrival() {
        guard isNavigating, !hasArrived else { return }
        
        hasArrived = true
        arrivalTickCount = 0
        bleController?.log("🏁 Arrived at destination '\(destinationName)'! Triggering dashboard arrival sequence.")
        
        // Send immediate arrival packet
        sendArrivalPacket()
    }
    
    func resendCurrentState() {
        guard isNavigating, activeRoute != nil else { return }
        
        bleController?.log("🔄 Resending navigation state to TFT dashboard after reconnect...")
        sendDestinationPacket(destinationName)
        lastSentSignature = "" // force resend
        sendManeuverUpdate()
    }
    
    // MARK: - Timer Tick & Pacing (matching Android l1.java)
    
    private func startTimer() {
        stopTimer()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.handleTimerTick()
        }
    }
    
    private func stopTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func handleTimerTick() {
        tickCounter += 1
        
        if hasArrived {
            // Arrival sequence: alternate "Arrived" and destination name 5 times (every 3 seconds), then end
            if arrivalTickCount % 3 == 0 {
                sendArrivalPacket()
            }
            arrivalTickCount += 1
            if arrivalTickCount >= 15 {
                bleController?.log("🏁 Arrival display complete. Sending end navigation packet.")
                stopNavigation()
            }
            return
        }
        
        guard isNavigating else { return }
        
        // Keep-alive: resend Destination packet (act 1) every 15 seconds
        if tickCounter % 15 == 0 {
            sendDestinationPacket(destinationName)
        }
        
        // Maneuver update: send every tick if state changed, or at least every 5 seconds as keep-alive
        let forceSend = (tickCounter % 5 == 0)
        sendManeuverUpdate(forceSend: forceSend)
    }
    
    // MARK: - Packet Generation & Formatting
    
    private func sendDestinationPacket(_ name: String) {
        guard let ble = bleController, ble.connectionState == .connected else { return }
        ble.sendNavigationDestination(name)
        lastDestinationSentTime = Date()
    }
    
    private func sendManeuverUpdate(forceSend: Bool = false) {
        guard let ble = bleController, ble.connectionState == .connected, let route = activeRoute else { return }
        guard currentStepIndex < route.steps.count else { return }
        
        let step = route.steps[currentStepIndex]
        let rawIcon = mapStepToKoveIcon(step: step)
        let nextRoad = extractRoadName(from: step.instructions)
        
        let stepMeters = max(0, Int(distanceToNextStepMeters))
        let totalMeters = max(0, Int(distanceRemainingMeters))
        
        let smoothedStepMeters = smoothDistance(stepMeters)
        let smoothedTotalMeters = smoothDistance(totalMeters)
        
        // Approaching threshold smoothing matching Android m1.java:
        // Only show turn icon (left, right, etc.) when approaching junction (<= 300m or speed based).
        // While cruising far away, show straight icon (9).
        let approachThreshold: Int
        if lastUserSpeedKmH <= 50 {
            approachThreshold = 300
        } else if lastUserSpeedKmH > 90 {
            approachThreshold = 500
        } else {
            approachThreshold = max(50, (lastUserSpeedKmH * 10000) / 3600)
        }
        
        let displayIcon: Int
        let isArrivalIcon = (rawIcon == 21 || rawIcon == 22 || rawIcon == 23)
        if !isArrivalIcon && smoothedStepMeters > approachThreshold {
            displayIcon = KoveNaviIcon.straight.rawValue // 9
        } else {
            displayIcon = rawIcon
        }
        
        // Format maneuver distance
        let curRetainDistanceStr: String
        let curUnitType: Int // 0: meters, 1: km
        if smoothedStepMeters < 1000 {
            curRetainDistanceStr = "\(smoothedStepMeters)"
            curUnitType = 0
        } else {
            let km = floor(Double(smoothedStepMeters) / 100.0) / 10.0
            curRetainDistanceStr = String(format: "%.1f", locale: Locale(identifier: "en_US"), km)
            curUnitType = 1
        }
        
        // Format total remaining distance
        let pathRetainDistanceStr: String
        let pathUnitType: Int // 0: meters, 1: km
        if smoothedTotalMeters < 1000 {
            pathRetainDistanceStr = "\(smoothedTotalMeters)"
            pathUnitType = 0
        } else {
            let km = Double(smoothedTotalMeters) / 1000.0
            pathRetainDistanceStr = String(format: "%.1f", locale: Locale(identifier: "en_US"), km)
            pathUnitType = 1
        }
        
        // Progress rate percentage (0..100)
        let totalRouteDistance = max(1, Int(route.distance))
        let retainRate = max(0, min(100, 100 - Int((Double(smoothedTotalMeters) * 100.0) / Double(totalRouteDistance))))
        
        // Remaining travel time & arrival timestamp
        let curRetainTime = max(0, Int(timeRemainingSeconds))
        let remainTime = Int64(Date().timeIntervalSince1970) + Int64(curRetainTime)
        
        // Signature check to avoid sending redundant duplicate packets over BLE
        let signature = "\(displayIcon)|\(curRetainDistanceStr)|\(nextRoad)|\(pathRetainDistanceStr)|\(retainRate)"
        if !forceSend && signature == lastSentSignature {
            return
        }
        lastSentSignature = signature
        
        ble.sendNavigationManeuver(
            icon: displayIcon,
            nextRoad: nextRoad,
            curRoad: "",
            retainRate: retainRate,
            curRetainDistance: curRetainDistanceStr,
            curUnitType: curUnitType,
            pathRetainDistance: pathRetainDistanceStr,
            pathCurUnitType: pathUnitType,
            curRetainTime: curRetainTime,
            remainTime: remainTime
        )
    }
    
    private func sendArrivalPacket() {
        guard let ble = bleController, ble.connectionState == .connected else { return }
        
        let label = (arrivalTickCount % 2 == 0) ? "Arrived" : destinationName
        let nextRoad = KoveTextSanitizer.sanitize(label)
        let remainTime = Int64(Date().timeIntervalSince1970)
        
        ble.sendNavigationManeuver(
            icon: KoveNaviIcon.arrived.rawValue, // 21
            nextRoad: nextRoad,
            curRoad: "",
            retainRate: 100,
            curRetainDistance: "0",
            curUnitType: 0,
            pathRetainDistance: "0",
            pathCurUnitType: 0,
            curRetainTime: 0,
            remainTime: remainTime
        )
    }
    
    // MARK: - Distance Smoothing & Icon Mapping Helpers
    
    private func smoothDistance(_ meters: Int) -> Int {
        if meters < 300 {
            return (meters / 10) * 10
        } else if meters < 1000 {
            return (meters / 50) * 50
        } else {
            return (meters / 100) * 100
        }
    }
    
    private func mapStepToKoveIcon(step: MKRoute.Step) -> Int {
        let lower = step.instructions.lowercased()
        
        // Arrival
        if lower.contains("arrive") || lower.contains("destination") {
            if lower.contains("left") { return KoveNaviIcon.arrivedLeft.rawValue }
            if lower.contains("right") { return KoveNaviIcon.arrivedRight.rawValue }
            return KoveNaviIcon.arrived.rawValue
        }
        
        // U-Turn
        if lower.contains("u-turn") || lower.contains("uturn") {
            return KoveNaviIcon.uTurn.rawValue
        }
        
        // Roundabout
        if lower.contains("roundabout") || lower.contains("rotary") || lower.contains("circle") {
            let exitRules: [(String, KoveNaviIcon)] = [
                ("1st", .roundaboutExit1), ("first", .roundaboutExit1), ("exit 1", .roundaboutExit1),
                ("2nd", .roundaboutExit2), ("second", .roundaboutExit2), ("exit 2", .roundaboutExit2),
                ("3rd", .roundaboutExit3), ("third", .roundaboutExit3), ("exit 3", .roundaboutExit3),
                ("4th", .roundaboutExit4), ("fourth", .roundaboutExit4), ("exit 4", .roundaboutExit4),
                ("5th", .roundaboutExit5), ("fifth", .roundaboutExit5), ("exit 5", .roundaboutExit5),
                ("6th", .roundaboutExit6), ("sixth", .roundaboutExit6), ("exit 6", .roundaboutExit6),
                ("7th", .roundaboutExit7), ("seventh", .roundaboutExit7), ("exit 7", .roundaboutExit7),
                ("8th", .roundaboutExit8), ("eighth", .roundaboutExit8), ("exit 8", .roundaboutExit8),
                ("9th", .roundaboutExit9), ("ninth", .roundaboutExit9), ("exit 9", .roundaboutExit9),
                ("10th", .roundaboutExit10), ("tenth", .roundaboutExit10), ("exit 10", .roundaboutExit10),
                ("11th", .roundaboutExit11), ("eleventh", .roundaboutExit11), ("exit 11", .roundaboutExit11),
                ("12th", .roundaboutExit12), ("twelfth", .roundaboutExit12), ("exit 12", .roundaboutExit12)
            ]
            for (key, icon) in exitRules {
                if lower.contains(key) {
                    return icon.rawValue
                }
            }
            return KoveNaviIcon.roundaboutGeneric.rawValue
        }
        
        // Ramps / Freeways
        if lower.contains("ramp") || lower.contains("exit") {
            if lower.contains("left") { return KoveNaviIcon.rampLeft.rawValue }
            if lower.contains("right") { return KoveNaviIcon.rampRight.rawValue }
        }
        
        // Forks / Keep lanes
        if lower.contains("keep") || lower.contains("fork") || lower.contains("bear") {
            if lower.contains("left") { return KoveNaviIcon.forkLeft.rawValue }
            if lower.contains("right") { return KoveNaviIcon.forkRight.rawValue }
        }
        
        // Sharp turns
        if lower.contains("sharp") {
            if lower.contains("left") { return KoveNaviIcon.sharpLeft.rawValue }
            if lower.contains("right") { return KoveNaviIcon.sharpRight.rawValue }
        }
        
        // Slight turns
        if lower.contains("slight") {
            if lower.contains("left") { return KoveNaviIcon.slightLeft.rawValue }
            if lower.contains("right") { return KoveNaviIcon.slightRight.rawValue }
        }
        
        // Regular turns
        if lower.contains("left") {
            return KoveNaviIcon.turnLeft.rawValue
        }
        if lower.contains("right") {
            return KoveNaviIcon.turnRight.rawValue
        }
        
        // Straight / Continue
        return KoveNaviIcon.straight.rawValue
    }
    
    private func extractRoadName(from instruction: String) -> String {
        let lower = instruction.lowercased()
        let prefixes = ["onto ", "toward ", "towards ", "on ", "to "]
        for prefix in prefixes {
            if let range = lower.range(of: prefix) {
                let road = instruction[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !road.isEmpty {
                    return KoveTextSanitizer.sanitize(road)
                }
            }
        }
        return KoveTextSanitizer.sanitize(instruction)
    }
}
