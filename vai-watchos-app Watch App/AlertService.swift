//
//  AlertService.swift
//  vai-watchos-app Watch App
//
//  Created by Michele Mincone on 22/10/25.
//

import Foundation
import CoreLocation
import Combine

/// Main service that coordinates shake detection, location capture, and alert emission
/// This is the primary controller for the VAI alert system
@MainActor
final class AlertService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastAlertDate: Date?
    @Published private(set) var alertCount: Int = 0
    @Published private(set) var status: ServiceStatus = .idle
    @Published var error: ServiceError?

    // MARK: - Managers

    private let motionManager: MotionManager
    private let locationManager: LocationManager
    private let webSocketManager: WebSocketManager

    private let logger = Logger(subsystem: "com.example.vaiwatchos", category: "AlertService")

    // MARK: - Status

    enum ServiceStatus: Equatable {
        case idle
        case monitoring
        case processingAlert
        case sendingAlert
        case alertSent
        case error(String)

        var displayText: String {
            switch self {
            case .idle:
                return "Tap to start monitoring"
            case .monitoring:
                return "Monitoring for shake..."
            case .processingAlert:
                return "Shake detected!"
            case .sendingAlert:
                return "Sending alert..."
            case .alertSent:
                return "Alert sent!"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }

    // MARK: - Initialization

    init(
        motionManager: MotionManager = MotionManager(),
        locationManager: LocationManager = LocationManager(),
        webSocketManager: WebSocketManager = WebSocketManager()
    ) {
        self.motionManager = motionManager
        self.locationManager = locationManager
        self.webSocketManager = webSocketManager

        setupShakeDetection()
        logger.info("AlertService initialized")
    }

    // MARK: - Public Methods

    /// Starts the alert monitoring service
    func startMonitoring() {
        guard !isActive else {
            logger.warning("Monitoring already active")
            return
        }

        logger.info("Starting alert monitoring service")

        // Connect to WebSocket
        webSocketManager.connect()

        // Start motion monitoring
        motionManager.startMonitoring()

        isActive = true
        status = .monitoring

        logger.info("Alert monitoring service started")
    }

    /// Stops the alert monitoring service
    func stopMonitoring() {
        guard isActive else {
            logger.warning("Monitoring not active")
            return
        }

        logger.info("Stopping alert monitoring service")

        // Stop motion monitoring
        motionManager.stopMonitoring()

        // Stop location updates
        locationManager.stopLocationUpdates()

        // Disconnect WebSocket
        webSocketManager.disconnect()

        isActive = false
        status = .idle

        logger.info("Alert monitoring service stopped")
    }

    /// Toggles monitoring on/off
    func toggleMonitoring() {
        if isActive {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    // MARK: - Private Methods

    private func setupShakeDetection() {
        motionManager.onShakeDetected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleShakeDetected()
            }
        }
    }

    private func handleShakeDetected() async {
        guard isActive else { return }

        logger.info("Processing shake detection event")
        status = .processingAlert

        do {
            // Step 1: Get current location
            logger.info("Requesting current location")
            let location = try await locationManager.requestCurrentLocation()

            logger.info("Location captured: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")

            // Step 2: Generate unique user ID
            let userId = UUID().uuidString

            // Step 3: Send alert via WebSocket
            status = .sendingAlert
            try await webSocketManager.emitAlert(
                userId: userId,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            // Step 4: Update state
            lastAlertDate = Date()
            alertCount += 1
            status = .alertSent

            logger.info("Alert sent successfully. Total alerts: \(alertCount)")

            // Show success briefly, then return to monitoring
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if status == .alertSent && isActive {
                status = .monitoring
            }

        } catch let error as LocationManager.LocationError {
            handleError(.locationError(error.localizedDescription ?? "Unknown location error"))
        } catch let error as WebSocketManager.WebSocketError {
            handleError(.webSocketError(error.localizedDescription ?? "Unknown WebSocket error"))
        } catch {
            handleError(.unknown(error.localizedDescription))
        }
    }

    private func handleError(_ error: ServiceError) {
        logger.error("Service error: \(error.displayMessage)")

        self.error = error
        status = .error(error.displayMessage)

        // Return to monitoring after showing error
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if status.displayText.contains("Error") && isActive {
                self.error = nil
                status = .monitoring
            }
        }
    }

    // MARK: - Error Handling

    enum ServiceError: LocalizedError, Equatable {
        case locationError(String)
        case webSocketError(String)
        case notMonitoring
        case unknown(String)

        var displayMessage: String {
            switch self {
            case .locationError(let message):
                return "Location: \(message)"
            case .webSocketError(let message):
                return "Network: \(message)"
            case .notMonitoring:
                return "Service not monitoring"
            case .unknown(let message):
                return message
            }
        }

        var errorDescription: String? {
            displayMessage
        }
    }

    // MARK: - Deinitialization

    deinit {
        // Note: Cannot call async methods in deinit
        // Cleanup will happen when managers are deallocated
        motionManager.stopMonitoring()
        locationManager.stopLocationUpdates()
        webSocketManager.disconnect()
        logger.info("AlertService deinitialized")
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
