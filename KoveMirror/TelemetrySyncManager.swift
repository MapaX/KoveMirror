import Foundation
import CoreLocation
import Combine

class TelemetrySyncManager: ObservableObject {
    static let shared = TelemetrySyncManager()
    
    @Published var currentAltitudeMeters: Int = 0
    @Published var currentTemperatureCelsius: Int? = nil
    @Published var currentWeatherCode: Int = 1 // 1 = Clear/Sunny default
    @Published var currentWindPower: String = "0"
    @Published var weatherIconName: String = "sun.max.fill"
    
    private var syncTimer: Timer?
    private var weatherFetchTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastFetchedCoordinate: CLLocationCoordinate2D?
    private var lastSentAltitude: Int?
    
    weak var bleController: BleController?
    
    private init() {
        setupLocationObserver()
    }
    
    func startSync(bleController: BleController) {
        self.bleController = bleController
        
        syncTimer?.invalidate()
        weatherFetchTimer?.invalidate()
        
        // Fetch weather immediately if needed
        fetchWeatherIfNeeded()
        
        // Send initial telemetry packet if data is already available
        sendTelemetryPackets()
        
        // Periodic sync to refresh TFT display every 30 seconds
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendTelemetryPackets()
        }
        
        // Refresh weather API data every 10 minutes (600s)
        weatherFetchTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            self?.fetchWeatherIfNeeded()
        }
        
        print("🌡️ Telemetry Sync Manager started (Periodic sync every 30s).")
        bleController.log("🌡️ Telemetry Sync Manager started (Periodic sync every 30s).")
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
                        // If altitude changed significantly (>= 3m) and BLE is active, sync immediately
                        if let lastAlt = self.lastSentAltitude, abs(alt - lastAlt) >= 3,
                           self.bleController?.connectionState == .connected {
                            self.sendTelemetryPackets()
                        }
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
        
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m"
        guard let url = URL(string: urlStr) else { return }
        
        bleController?.log("🌐 Fetching weather for coordinates: (\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon)))...")
        print("🌐 Fetching weather for coordinates: (\(lat), \(lon))...")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.bleController?.log("❌ Weather API network error: \(error.localizedDescription)")
                print("❌ Weather API network error: \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current"] as? [String: Any],
                   let tempDouble = current["temperature_2m"] as? Double,
                   let weatherCodeInt = current["weather_code"] as? Int {
                    
                    let windSpeed = current["wind_speed_10m"] as? Double ?? 0.0
                    let windPowerStr = "\(Int(round(windSpeed)))"
                    let tempInt = Int(round(tempDouble))
                    let mappedKoveWeather = self.mapOpenMeteoToKoveWeather(code: weatherCodeInt)
                    let icon = self.mapWeatherCodeToIcon(koveCode: mappedKoveWeather)
                    
                    DispatchQueue.main.async {
                        self.currentTemperatureCelsius = tempInt
                        self.currentWeatherCode = mappedKoveWeather
                        self.currentWindPower = windPowerStr
                        self.weatherIconName = icon
                        self.bleController?.log("🌡️ Weather fetched: \(tempInt)°C (Kove code: \(mappedKoveWeather), wind: \(windPowerStr) km/h)")
                        print("🌡️ Weather fetched: \(tempInt)°C, Weather Code: \(mappedKoveWeather)")
                        self.sendTelemetryPackets()
                    }
                }
            } catch {
                self.bleController?.log("❌ Weather parsing error: \(error.localizedDescription)")
                print("❌ Weather parsing error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Telemetry JSON Packet Formatting (Matching ThinkerRide / TinkerAPP)
    
    func sendTelemetryPackets() {
        guard let ble = bleController, ble.connectionState == .connected else {
            return
        }
        
        let alt = currentAltitudeMeters
        lastSentAltitude = alt
        
        // 1. Elevation & Altitude Packet (JsonManager.sendElevationAndPond: msg_id 25, msg_type 9)
        let altJson = "{\"msg_id\":25,\"msg_type\":9,\"msg_source\":2,\"altitude\":\(alt),\"ave_altitude\":0,\"max_altitude\":0,\"pond_distance\":0.0,\"pond_time\":0,\"head\":0}"
        ble.sendJsonPacket(altJson)
        
        // 2. Weather & Temperature Packets (matching TinkerAPP: sendWeatherWithWindPower and sendWeather)
        if let temp = currentTemperatureCelsius {
            let tempStr = "\(temp)" // Integer string (e.g. "20" or "-5") without "°C"
            let wCode = currentWeatherCode
            let windStr = currentWindPower
            
            // Format A: Extended Weather with Wind Power (JsonManager.sendWeatherWithWindPower: msg_id 25, msg_type 11)
            let weatherWindJson = "{\"msg_id\":25,\"msg_type\":11,\"msg_source\":2,\"weather\":\(wCode),\"temperature\":\"\(tempStr)\",\"wind_power\":\"\(windStr)\"}"
            ble.sendJsonPacket(weatherWindJson)
            
            // Format B: Standard Weather (JsonManager.sendWeather: msg_id 8)
            let weatherJson = "{\"msg_id\":8,\"weather\":\(wCode),\"temperature\":\"\(tempStr)\"}"
            ble.sendJsonPacket(weatherJson)
            
            ble.log("📤 Telemetry Synced to TFT -> Alt: \(alt)m | Temp: \(tempStr)°C | Weather Code: \(wCode)")
            print("📤 Telemetry Synced to TFT -> Alt: \(alt)m | Temp: \(tempStr)°C | Weather Code: \(wCode)")
        } else {
            ble.log("📤 Telemetry Synced to TFT -> Alt: \(alt)m (Weather pending)")
            print("📤 Telemetry Synced to TFT -> Alt: \(alt)m (Weather pending)")
        }
    }
    
    // MARK: - Weather Code Mapping (Matching TinkerAPP WeatherUtil.java)
    // 1: sunny, 2: rainy, 3: cloudy, 4: snowy, 5: cloudy_sunny, 6: thunder_rainy, 7: overcast, 8: dense_fog
    
    private func mapOpenMeteoToKoveWeather(code: Int) -> Int {
        switch code {
        case 0:
            return 1 // Sunny / Clear
        case 1, 2:
            return 5 // Partly Cloudy (Cloudy / Sunny)
        case 3:
            return 7 // Overcast
        case 45, 48:
            return 8 // Dense Fog
        case 51...67, 80...82:
            return 2 // Rain / Drizzle / Showers
        case 71...77, 85...86:
            return 4 // Snow
        case 95...99:
            return 6 // Thunderstorm
        default:
            return 1 // Clear default
        }
    }
    
    private func mapWeatherCodeToIcon(koveCode: Int) -> String {
        switch koveCode {
        case 1: return "sun.max.fill"
        case 2: return "cloud.rain.fill"
        case 3: return "cloud.fill"
        case 4: return "snowflake"
        case 5: return "cloud.sun.fill"
        case 6: return "cloud.bolt.rain.fill"
        case 7: return "smoke.fill"
        case 8: return "cloud.fog.fill"
        default: return "sun.max.fill"
        }
    }
}
