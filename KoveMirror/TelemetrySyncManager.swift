import Foundation
import CoreLocation
import Combine

class TelemetrySyncManager: ObservableObject {
    static let shared = TelemetrySyncManager()
    
    @Published var currentAltitudeMeters: Int = 0
    @Published var currentTemperatureCelsius: Int? = nil
    @Published var currentWeatherCode: Int = 1 // 1 = Clear/Sunny default
    @Published var weatherIconName: String = "sun.max.fill"
    
    private var syncTimer: Timer?
    private var weatherFetchTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastFetchedCoordinate: CLLocationCoordinate2D?
    
    weak var bleController: BleController?
    
    private init() {
        setupLocationObserver()
    }
    
    func startSync(bleController: BleController) {
        self.bleController = bleController
        
        syncTimer?.invalidate()
        weatherFetchTimer?.invalidate()
        
        // Local weather fetch for in-app UI display only
        fetchWeatherIfNeeded()
        
        // Refresh weather API data every 10 minutes for in-app display
        weatherFetchTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            self?.fetchWeatherIfNeeded()
        }
        
        print("🌡️ Telemetry Manager active (Local display only, BLE packets disabled).")
        bleController.log("ℹ️ Weather BLE packet sending is disabled.")
    }
    
    func stopSync() {
        syncTimer?.invalidate()
        weatherFetchTimer?.invalidate()
        syncTimer = nil
        weatherFetchTimer = nil
        print("🌡️ Telemetry Sync Manager stopped.")
        bleController?.log("🌡️ Telemetry Sync Manager stopped.")
    }
    
    private func setupLocationObserver() {
        LocationAndNavigationManager.shared.$userLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self = self else { return }
                let alt = Int(location.altitude)
                if alt != self.currentAltitudeMeters {
                    DispatchQueue.main.async {
                        self.currentAltitudeMeters = alt
                    }
                }
                self.fetchWeatherIfNeeded(location: location)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - OpenMeteo Weather API (Free, zero API key required)
    
    private func fetchWeatherIfNeeded(location: CLLocation? = LocationAndNavigationManager.shared.userLocation) {
        guard let location = location else { return }
        
        // Avoid duplicate queries if location hasn't moved significantly (> 5 km)
        if let lastCoord = lastFetchedCoordinate {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if location.distance(from: lastLoc) < 5000 && currentTemperatureCelsius != nil {
                return
            }
        }
        
        lastFetchedCoordinate = location.coordinate
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code"
        guard let url = URL(string: urlStr) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ Weather API network error: \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current"] as? [String: Any],
                   let tempDouble = current["temperature_2m"] as? Double,
                   let weatherCodeInt = current["weather_code"] as? Int {
                    
                    let tempInt = Int(round(tempDouble))
                    let mappedKoveWeather = self.mapOpenMeteoToKoveWeather(code: weatherCodeInt)
                    let icon = self.mapWeatherCodeToIcon(code: weatherCodeInt)
                    
                    DispatchQueue.main.async {
                        self.currentTemperatureCelsius = tempInt
                        self.currentWeatherCode = mappedKoveWeather
                        self.weatherIconName = icon
                        print("🌡️ Weather fetched: \(tempInt)°C, Weather Code: \(mappedKoveWeather)")
                    }
                }
            } catch {
                print("❌ Weather parsing error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Telemetry JSON Packet Formatting (Disabled)
    
    func sendTelemetryPackets() {
        // Disabled per user request - no weather BLE packets are sent to motorcycle TFT
    }
    
    // MARK: - Weather Code Mapping
    
    private func mapOpenMeteoToKoveWeather(code: Int) -> Int {
        switch code {
        case 0, 1: return 1 // Clear / Sunny
        case 2, 3: return 2 // Overcast / Cloudy
        case 51...67, 80...82: return 3 // Rain / Drizzle
        case 71...77, 85...86: return 4 // Snow
        case 95...99: return 5 // Thunderstorm
        default: return 1
        }
    }
    
    private func mapWeatherCodeToIcon(code: Int) -> String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2, 3: return "cloud.sun.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85...86: return "snowflake"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "sun.max.fill"
        }
    }
}
