import Foundation
import CoreLocation
import MapKit
import AVFoundation
import Combine

struct NavigationStepInfo: Identifiable {
    let id = UUID()
    let instruction: String
    let distanceMeters: CLLocationDistance
    let iconName: String
}

class LocationAndNavigationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationAndNavigationManager()
    
    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    // Location & Heading
    @Published var userLocation: CLLocation?
    @Published var userHeading: CLHeading?
    @Published var currentSpeedKmH: Int = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Route & Navigation State
    @Published var isNavigating: Bool = false
    @Published var destinationItem: MKMapItem?
    @Published var currentRoute: MKRoute?
    @Published var currentStepIndex: Int = 0
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var distanceRemainingMeters: CLLocationDistance = 0
    @Published var timeRemainingSeconds: TimeInterval = 0
    @Published var isAudioMuted: Bool = false
    
    // Computed Current Step
    var currentStep: MKRoute.Step? {
        guard let route = currentRoute, currentStepIndex < route.steps.count else { return nil }
        return route.steps[currentStepIndex]
    }
    
    var nextStep: MKRoute.Step? {
        guard let route = currentRoute, (currentStepIndex + 1) < route.steps.count else { return nil }
        return route.steps[currentStepIndex + 1]
    }
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2.0 // Update every 2 meters
        locationManager.headingFilter = 3.0   // Update every 3 degrees
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        
        self.authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            startUpdating()
        }
    }
    
    func startUpdating() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - Route Calculation
    
    func calculateRoute(to destination: MKMapItem, completion: @escaping (Result<MKRoute, Error>) -> Void) {
        guard let originLocation = userLocation else {
            let error = NSError(domain: "LocationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "User location unavailable. Make sure location permissions are enabled."])
            completion(.failure(error))
            return
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: originLocation.coordinate))
        request.destination = destination
        request.transportType = .automobile // Default to road routing suitable for motorcycles
        request.requestsAlternateRoutes = true
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let route = response?.routes.first else {
                let err = NSError(domain: "LocationManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No route found to destination."])
                completion(.failure(err))
                return
            }
            
            DispatchQueue.main.async {
                self?.destinationItem = destination
                self?.currentRoute = route
            }
            completion(.success(route))
        }
    }
    
    // MARK: - Navigation Control
    
    func startNavigation(route: MKRoute, destination: MKMapItem) {
        self.currentRoute = route
        self.destinationItem = destination
        self.currentStepIndex = 0
        self.isNavigating = true
        self.distanceRemainingMeters = route.distance
        self.timeRemainingSeconds = route.expectedTravelTime
        
        startUpdating()
        
        // Announce navigation start
        let destName = destination.name ?? "destination"
        speakInstruction("Starting route to \(destName). Ride safely.")
        
        if let firstStep = currentStep {
            updateStepInfo(step: firstStep)
        }
    }
    
    func stopNavigation() {
        isNavigating = false
        currentRoute = nil
        destinationItem = nil
        currentStepIndex = 0
        speakInstruction("Navigation ended.")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.startUpdating()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.userLocation = location
            
            // Speed in km/h
            let speedMs = max(0, location.speed)
            self.currentSpeedKmH = Int(speedMs * 3.6)
            
            // If navigating, update route progress & step transitions
            if self.isNavigating {
                self.updateNavigationProgress(currentLocation: location)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.userHeading = newHeading
        }
    }
    
    // MARK: - Navigation Step Tracking
    
    private func updateNavigationProgress(currentLocation: CLLocation) {
        guard let route = currentRoute else { return }
        
        // Check distance to destination
        if let destLocation = destinationItem?.placemark.location {
            let totalRemaining = currentLocation.distance(from: destLocation)
            self.distanceRemainingMeters = totalRemaining
            
            // Arrival threshold (30 meters)
            if totalRemaining < 30 {
                speakInstruction("You have arrived at your destination.")
                stopNavigation()
                return
            }
        }
        
        guard currentStepIndex < route.steps.count else { return }
        let step = route.steps[currentStepIndex]
        
        // Calculate distance to end of current step
        let stepEndPoint = getStepCoordinate(step: step)
        let distanceToStepEnd = currentLocation.distance(from: stepEndPoint)
        self.distanceToNextStep = distanceToStepEnd
        
        // Advance step if within 25m of maneuver point
        if distanceToStepEnd < 25 && currentStepIndex < (route.steps.count - 1) {
            currentStepIndex += 1
            if let newStep = currentStep {
                updateStepInfo(step: newStep)
            }
        }
    }
    
    private func updateStepInfo(step: MKRoute.Step) {
        guard !step.instructions.isEmpty else { return }
        let distanceKm = String(format: "%.1f km", step.distance / 1000.0)
        let distText = step.distance < 1000 ? "\(Int(step.distance)) meters" : distanceKm
        
        speakInstruction("In \(distText), \(step.instructions)")
    }
    
    private func getStepCoordinate(step: MKRoute.Step) -> CLLocation {
        let pointCount = step.polyline.pointCount
        guard pointCount > 0 else { return userLocation ?? CLLocation() }
        let points = step.polyline.points()
        let lastPoint = points[pointCount - 1]
        return CLLocation(latitude: lastPoint.coordinate.latitude, longitude: lastPoint.coordinate.longitude)
    }
    
    private func speakInstruction(_ text: String) {
        guard !isAudioMuted else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.languageCode ?? "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
}

// Helper extension for maneuver icon mapping
extension MKRoute.Step {
    var maneuverIconName: String {
        let lower = instructions.lowercased()
        if lower.contains("right") {
            return "arrow.turn.up.right"
        } else if lower.contains("left") {
            return "arrow.turn.up.left"
        } else if lower.contains("roundabout") || lower.contains("circle") {
            return "arrow.triangle.turn.clockwise.around.railway"
        } else if lower.contains("u-turn") {
            return "arrow.uturn.backward"
        } else if lower.contains("merge") || lower.contains("keep") {
            return "arrow.triangle.merge"
        } else if lower.contains("arrive") || lower.contains("destination") {
            return "mappin.circle.fill"
        } else {
            return "arrow.up"
        }
    }
}
