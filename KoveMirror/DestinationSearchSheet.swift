import SwiftUI
import MapKit
import Combine

class SearchCompleterDelegate: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func search(query: String, region: MKCoordinateRegion?) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        if let region = region {
            completer.region = region
        }
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
            self.isSearching = false
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }
}

struct DestinationSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completerDelegate = SearchCompleterDelegate()
    @State private var query: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isPerformingSearch = false
    
    let userRegion: MKCoordinateRegion?
    let onSelectDestination: (MKMapItem) -> Void
    
    let categories: [(name: String, icon: String, query: String, color: Color)] = [
        ("Gas Stations", "fuelpump.fill", "Gas Station", .orange),
        ("Coffee", "cup.and.saucer.fill", "Coffee Shop", .brown),
        ("Parking", "parkingsign.circle.fill", "Motorcycle Parking", .blue),
        ("Food", "fork.knife", "Restaurant", .green)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0D0D11").ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.4))
                        
                        TextField("Search destination or address...", text: $query)
                            .foregroundColor(.white)
                            .onChange(of: query) { oldValue, newValue in
                                completerDelegate.search(query: newValue, region: userRegion)
                            }
                        
                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Category Buttons Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(categories, id: \.name) { cat in
                                Button(action: { performCategorySearch(cat.query) }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.icon)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(cat.color)
                                        Text(cat.name)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(cat.color.opacity(0.15))
                                    .cornerRadius(20)
                                    .overlay(
                                        Capsule()
                                            .stroke(cat.color.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Search Results List
                    if isPerformingSearch || completerDelegate.isSearching {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            Text("Searching locations...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                    } else if !searchResults.isEmpty {
                        // Category Search Results
                        List {
                            ForEach(searchResults, id: \.self) { item in
                                MapItemRow(item: item) {
                                    onSelectDestination(item)
                                    dismiss()
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.04))
                        }
                        .listStyle(.plain)
                    } else if !completerDelegate.results.isEmpty {
                        // Autocomplete Search Results
                        List {
                            ForEach(completerDelegate.results, id: \.subtitle) { completion in
                                Button(action: { selectCompletion(completion) }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.orange)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(completion.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                            
                                            if !completion.subtitle.isEmpty {
                                                Text(completion.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(Color.white.opacity(0.04))
                            }
                        }
                        .listStyle(.plain)
                    } else {
                        // Empty State / Instructions
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "map.circle.fill")
                                .font(.system(size: 54))
                                .foregroundColor(.orange.opacity(0.4))
                            
                            Text("Find Your Route")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Type an address, city, or choose a category above to set your destination for motorcycle navigation.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Set Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        isPerformingSearch = true
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isPerformingSearch = false
                if let item = response?.mapItems.first {
                    self.onSelectDestination(item)
                    self.dismiss()
                }
            }
        }
    }
    
    private func performCategorySearch(_ categoryQuery: String) {
        isPerformingSearch = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = categoryQuery
        if let region = userRegion {
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isPerformingSearch = false
                if let items = response?.mapItems {
                    self.searchResults = items
                }
            }
        }
    }
}

struct MapItemRow: View {
    let item: MKMapItem
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Location")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.vertical, 4)
        }
    }
}
