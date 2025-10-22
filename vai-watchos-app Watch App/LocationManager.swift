//
//  LocationManager.swift
//  vai-watchos-app Watch App
//
//  Created by Michele Mincone on 22/10/25.
//

import Foundation
import CoreLocation
import Combine

/// Manages location services with high accuracy GPS tracking
/// Provides one-shot location capture optimized for watchOS
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var error: LocationError?

    // MARK: - Private Properties

    private let locationManager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private let logger = Logger(subsystem: "com.example.vaiwatchos", category: "LocationManager")

    // MARK: - Configuration

    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    private let timeout: TimeInterval = 10.0 // 10 seconds timeout

    // MARK: - Initialization

    override init() {
        self.locationManager = CLLocationManager()
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter

        // Request authorization if not determined
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        logger.info("LocationManager initialized")
    }

    // MARK: - Public Methods

    /// Requests current location with timeout
    /// - Returns: Current location
    /// - Throws: LocationError if unable to get location
    func requestCurrentLocation() async throws -> CLLocation {
        logger.info("Requesting current location")

        // Check authorization
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            logger.error("Location authorization denied")
            throw LocationError.authorizationDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation

            // Start location updates
            locationManager.startUpdatingLocation()

            // Set timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                if self.locationContinuation != nil {
                    self.locationContinuation = nil
                    locationManager.stopUpdatingLocation()
                    logger.warning("Location request timed out")
                    continuation.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    /// Stops location updates
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        logger.info("Location updates stopped")
    }

    /// Requests location authorization
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Error Handling

    enum LocationError: LocalizedError {
        case authorizationDenied
        case timeout
        case unavailable
        case accuracyReduced
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                return "Location access denied. Please enable location services in Settings."
            case .timeout:
                return "Location request timed out. Please try again."
            case .unavailable:
                return "Location services unavailable."
            case .accuracyReduced:
                return "Location accuracy is reduced. Enable precise location in Settings."
            case .unknown(let error):
                return "Location error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        logger.info("Authorization status changed: \(status.rawValue)")

        // Handle authorization changes
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.info("Location authorization granted")
        case .denied, .restricted:
            logger.warning("Location authorization denied or restricted")
            DispatchQueue.main.async {
                self.error = .authorizationDenied
            }
            if let continuation = locationContinuation {
                continuation.resume(throwing: LocationError.authorizationDenied)
                locationContinuation = nil
            }
        case .notDetermined:
            logger.info("Location authorization not determined")
        @unknown default:
            logger.warning("Unknown authorization status")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        logger.info("Location updated: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude), accuracy=\(location.horizontalAccuracy)m")

        DispatchQueue.main.async {
            self.lastLocation = location
        }

        // Resume continuation if waiting
        if let continuation = locationContinuation {
            locationContinuation = nil
            locationManager.stopUpdatingLocation()
            continuation.resume(returning: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location manager failed: \(error.localizedDescription)")

        let locationError: LocationError

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .authorizationDenied
            case .locationUnknown:
                locationError = .unavailable
            default:
                locationError = .unknown(error)
            }
        } else {
            locationError = .unknown(error)
        }

        DispatchQueue.main.async {
            self.error = locationError
        }

        // Resume continuation with error
        if let continuation = locationContinuation {
            locationContinuation = nil
            locationManager.stopUpdatingLocation()
            continuation.resume(throwing: locationError)
        }
    }
}

// MARK: - Logger Extension

private struct Logger {
    let subsystem: String
    let category: String

    func info(_ message: String) {
        print("ℹ️ [\(category)] \(message)")
    }

    func warning(_ message: String) {
        print("⚠️ [\(category)] \(message)")
    }

    func error(_ message: String) {
        print("❌ [\(category)] \(message)")
    }
}
