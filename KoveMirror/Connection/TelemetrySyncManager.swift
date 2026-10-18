import Foundation
import CoreLocation
import Combine
import UIKit

class TelemetrySyncManager: ObservableObject {
    static let shared = TelemetrySyncManager()
    
    @Published var currentAltitudeMeters: Int = 0
    @Published var currentTemperatureCelsius: Int? = nil
    @Published var currentWeatherCode: Int = 1 // 1 = Clear/Sunny default
    @Published var currentWindPower: String = "0"
    @Published var weatherIconName: String = "sun.max.fill"
    
    private let cachedAltitudeKey = "cached_altitude_meters"
    private let cachedTempKey = "cached_temp_celsius"
    private let cachedWeatherCodeKey = "cached_weather_code"
    private let cachedWindPowerKey = "cached_wind_power"
    private let cachedWeatherIconKey = "cached_weather_icon"
    private let cachedLatKey = "cached_location_lat"
    private let cachedLonKey = "cached_location_lon"
    
    private var syncTimer: Timer?
    private var weatherFetchTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastFetchedCoordinate: CLLocationCoordinate2D?
    private var lastSentAltitude: Int?
    
    weak var bleController: BleController?
    
    private init() {
        loadCachedTelemetry()
        setupLocationObserver()
    }
    
    func loadCachedTelemetry() {
        if UserDefaults.standard.object(forKey: cachedAltitudeKey) != nil {
            self.currentAltitudeMeters = UserDefaults.standard.integer(forKey: cachedAltitudeKey)
        }
        if UserDefaults.standard.object(forKey: cachedTempKey) != nil {
            self.currentTemperatureCelsius = UserDefaults.standard.integer(forKey: cachedTempKey)
        }
        if UserDefaults.standard.object(forKey: cachedWeatherCodeKey) != nil {
            self.currentWeatherCode = UserDefaults.standard.integer(forKey: cachedWeatherCodeKey)
        }
        if let wind = UserDefaults.standard.string(forKey: cachedWindPowerKey) {
            self.currentWindPower = wind
        }
        if let icon = UserDefaults.standard.string(forKey: cachedWeatherIconKey) {
            self.weatherIconName = icon
        }
    }
    
    private func saveCachedTelemetry(temp: Int, weatherCode: Int, windPower: String, icon: String, coordinate: CLLocationCoordinate2D) {
        UserDefaults.standard.set(temp, forKey: cachedTempKey)
        UserDefaults.standard.set(weatherCode, forKey: cachedWeatherCodeKey)
        UserDefaults.standard.set(windPower, forKey: cachedWindPowerKey)
        UserDefaults.standard.set(icon, forKey: cachedWeatherIconKey)
        UserDefaults.standard.set(coordinate.latitude, forKey: cachedLatKey)
        UserDefaults.standard.set(coordinate.longitude, forKey: cachedLonKey)
    }
    
    private func saveCachedAltitude(_ altitude: Int) {
        UserDefaults.standard.set(altitude, forKey: cachedAltitudeKey)
    }
    
    func startSync(bleController: BleController) {
        self.bleController = bleController
        
        syncTimer?.invalidate()
        weatherFetchTimer?.invalidate()
        
        // Start background location updates immediately
        LocationAndNavigationManager.shared.startUpdating()
        
        // Send initial telemetry packet immediately from cached/current state
        sendTelemetryPackets()
        
        // Fetch weather immediately if needed
        fetchWeatherIfNeeded(force: true)
        
        // Periodic sync to refresh TFT altitude & weather display every 30 seconds
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendTelemetryPackets()
        }
        
        // Refresh weather API data every 10 minutes (600s)
        weatherFetchTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            self?.fetchWeatherIfNeeded()
        }
        
        print("🌡️ Telemetry Sync Manager started (Periodic sync every 30s).")
        bleController.log("🌡️ Telemetry Sync Manager started. Initial Alt: \(currentAltitudeMeters)m, Temp: \(currentTemperatureCelsius.map { "\($0)°C" } ?? "pending").")
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
                        self.saveCachedAltitude(alt)
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
    
    private func fetchWeatherIfNeeded(location: CLLocation? = LocationAndNavigationManager.shared.userLocation, force: Bool = false) {
        let targetLocation: CLLocation?
        if let loc = location {
            targetLocation = loc
        } else if let cachedCoord = lastFetchedCoordinate {
            targetLocation = CLLocation(latitude: cachedCoord.latitude, longitude: cachedCoord.longitude)
        } else {
            targetLocation = nil
        }
        
        guard let location = targetLocation else { return }
        
        // Avoid duplicate queries if location hasn't moved significantly (> 5 km) unless forced
        if !force, let lastCoord = lastFetchedCoordinate {
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
        
        // Keep background process alive while fetching weather
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "WeatherFetchTask") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            defer {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
            
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
                        self.saveCachedTelemetry(temp: tempInt, weatherCode: mappedKoveWeather, windPower: windPowerStr, icon: icon, coordinate: location.coordinate)
                        
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
            ble.log("📤 Telemetry Synced to TFT -> Alt: \(alt)m (Temperature pending)")
            print("📤 Telemetry Synced to TFT -> Alt: \(alt)m (Temperature pending)")
        }
    }
    
    // MARK: - Protocol Mappings
    
    private func mapOpenMeteoToKoveWeather(code: Int) -> Int {
        switch code {
        case 0, 1:
            return 1 // Sunny / Clear
        case 2:
            return 2 // Partly Cloudy
        case 3:
            return 3 // Overcast / Cloudy
        case 45, 48:
            return 18 // Fog
        case 51, 53, 55, 56, 57:
            return 7 // Light Rain / Drizzle
        case 61, 63:
            return 8 // Moderate Rain
        case 65, 66, 67:
            return 9 // Heavy Rain
        case 71, 73, 75, 77, 85, 86:
            return 14 // Snow
        case 80, 81, 82:
            return 10 // Showers
        case 95, 96, 99:
            return 4 // Thunderstorm
        default:
            return 1 // Default to Clear
        }
    }
    
    private func mapWeatherCodeToIcon(koveCode: Int) -> String {
        switch koveCode {
        case 1:
            return "sun.max.fill"
        case 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 4:
            return "cloud.bolt.rain.fill"
        case 7, 8:
            return "cloud.rain.fill"
        case 9, 10:
            return "cloud.heavyrain.fill"
        case 14:
            return "snowflake"
        case 18:
            return "cloud.fog.fill"
        default:
            return "sun.max.fill"
        }
    }
}
