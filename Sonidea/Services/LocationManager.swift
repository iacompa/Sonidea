//
//  LocationManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/23/26.
//

import CoreLocation
import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class LocationManager: NSObject {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastKnownLocation: CLLocation?
    var isUpdatingLocation = false

    // Autocomplete
    var searchQuery: String = "" {
        didSet {
            if searchQuery.isEmpty {
                searchResults = []
                searchDebounceTask?.cancel()
            } else {
                debounceSearchQuery(searchQuery)
            }
        }
    }
    var searchResults: [MKLocalSearchCompletion] = []
    var isSearching = false

    private let locationManager = CLLocationManager()
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchDebounceTask: Task<Void, Never>?
    private var lastReverseGeocodeCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus

        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
    }

    // MARK: - Permission

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Location Updates

    func startUpdatingIfNeeded() {
        guard isAuthorized, !isUpdatingLocation else { return }
        isUpdatingLocation = true
        locationManager.requestLocation()
    }

    func stopUpdating() {
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        guard isAuthorized else { return }
        locationManager.requestLocation()
    }

    // MARK: - Geocoding

    func geocodeCompletion(_ completion: MKLocalSearchCompletion) async -> (coordinate: CLLocationCoordinate2D, label: String)? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }

            let label = [completion.title, completion.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            return (item.placemark.coordinate, label)
        } catch {
            #if DEBUG
            print("Geocode error: \(error)")
            #endif
            return nil
        }
    }

    func geocodeAddress(_ address: String) async -> (coordinate: CLLocationCoordinate2D, label: String)? {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let placemark = placemarks.first, let location = placemark.location else {
                return nil
            }

            var labelParts: [String] = []
            if let name = placemark.name { labelParts.append(name) }
            if let locality = placemark.locality { labelParts.append(locality) }
            let label = labelParts.isEmpty ? address : labelParts.joined(separator: ", ")

            return (location.coordinate, label)
        } catch {
            #if DEBUG
            print("Geocode error: \(error)")
            #endif
            return nil
        }
    }

    /// Cache for reverse geocode results keyed by rounded coordinate to avoid redundant API calls
    private var reverseGeocodeCache: [String: String] = [:]
    private static let maxCacheSize = 200

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        // Use rounded coordinates as cache key (~100m precision)
        let cacheKey = "\(String(format: "%.3f", coordinate.latitude)),\(String(format: "%.3f", coordinate.longitude))"
        if let cached = reverseGeocodeCache[cacheKey] {
            return cached
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            var labelParts: [String] = []
            if let name = placemark.name { labelParts.append(name) }
            if let locality = placemark.locality { labelParts.append(locality) }

            let result = labelParts.isEmpty ? nil : labelParts.joined(separator: ", ")
            if let result {
                reverseGeocodeCache[cacheKey] = result
                // Evict cache if it exceeds max size to prevent unbounded memory growth
                if reverseGeocodeCache.count > Self.maxCacheSize {
                    reverseGeocodeCache.removeAll()
                    reverseGeocodeCache[cacheKey] = result
                }
            }
            return result
        } catch {
            return nil
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchDebounceTask?.cancel()
    }

    // MARK: - Debounce Helpers

    /// Debounce search query updates to avoid rapid-fire MKLocalSearchCompleter requests
    private func debounceSearchQuery(_ query: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.searchCompleter.queryFragment = query
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastKnownLocation = location
            self.isUpdatingLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
        Task { @MainActor in
            self.isUpdatingLocation = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationManager: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.searchResults = completer.results
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}
