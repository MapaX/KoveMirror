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
        
        // Initial weather fetch & telemetry sync
        fetchWeatherIfNeeded()
        sendTelemetryPackets()
        
        // Sync telemetry to motorcycle TFT every 15 seconds
        syncTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sendTelemetryPackets()
        }
        
        // Refresh weather API data every 10 minutes
        weatherFetchTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            self?.fetchWeatherIfNeeded()
        }
        
        print("🌡️ Telemetry Sync Manager started (Altitude & Weather).")
    }
    
    func stopSync() {
        syncTimer?.invalidate()
        weatherFetchTimer?.invalidate()
        syncTimer = nil
        weatherFetchTimer = nil
        print("🌡️ Telemetry Sync Manager stopped.")
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
            guard let self = self, let data = data, error == nil else { return }
            
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
                        self.sendTelemetryPackets()
                    }
                }
            } catch {
                print("❌ Weather parsing error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Telemetry JSON Packet Formatting
    
    func sendTelemetryPackets() {
        guard let ble = bleController, ble.connectionState == .connected else { return }
        
        let alt = currentAltitudeMeters
        let tempStr = currentTemperatureCelsius.map { "\($0)°C" } ?? "--°C"
        let wCode = currentWeatherCode
        let speed = LocationAndNavigationManager.shared.currentSpeedKmH
        
        // 1. Weather & Temperature Packet (msg_id: 8)
        let weatherJson = "{\"msg_id\":8,\"weather\":\(wCode),\"temperature\":\"\(tempStr)\"}"
        ble.sendJsonPacket(weatherJson)
        
        // 2. Location & Altitude Telemetry Packet (msg_id: 27, func: CAR_INFO)
        if let loc = LocationAndNavigationManager.shared.userLocation {
            let latStr = String(format: "%.5f", loc.coordinate.latitude)
            let lonStr = String(format: "%.5f", loc.coordinate.longitude)
            let altJson = "{\"msg_id\":27,\"func\":\"CAR_INFO\",\"act\":\"set_location_info\",\"altitude\":\(alt),\"lat\":\(latStr),\"lon\":\(lonStr),\"speed\":\(speed)}"
            ble.sendJsonPacket(altJson)
        }
        
        print("📤 Telemetry Synced to TFT -> Altitude: \(alt)m | Temp: \(tempStr)")
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
