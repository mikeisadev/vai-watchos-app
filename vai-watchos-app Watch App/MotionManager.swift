//
//  MotionManager.swift
//  vai-watchos-app Watch App
//
//  Created by Michele Mincone on 22/10/25.
//

import Foundation
import CoreMotion
import Combine

/// Manages motion detection for shake gestures on watchOS
/// Uses accelerometer data to detect significant device movement
final class MotionManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastShakeDate: Date?

    // MARK: - Private Properties

    private let motionManager: CMMotionManager
    private let operationQueue: OperationQueue
    private let logger = Logger(subsystem: "com.example.vaiwatchos", category: "MotionManager")

    // MARK: - Configuration

    /// Shake detection threshold (in g-force units)
    /// Higher values = more aggressive shake required
    private let shakeThreshold: Double = 2.5 // Equivalent to ~12 m/s² from Android

    /// Update interval for accelerometer (in seconds)
    private let updateInterval: TimeInterval = 0.1 // 100ms

    /// Cooldown period between shake detections (in seconds)
    private let cooldownPeriod: TimeInterval = 1.0

    /// Callback for shake detection
    var onShakeDetected: (() -> Void)?

    // MARK: - Initialization

    init() {
        self.motionManager = CMMotionManager()
        self.operationQueue = OperationQueue()
        self.operationQueue.name = "com.vaiwatchos.motion"
        self.operationQueue.qualityOfService = .userInitiated

        configureMotionManager()
        logger.info("MotionManager initialized")
    }

    // MARK: - Configuration

    private func configureMotionManager() {
        motionManager.accelerometerUpdateInterval = updateInterval
    }

    // MARK: - Public Methods

    /// Starts monitoring for shake gestures
    func startMonitoring() {
        guard !isMonitoring else {
            logger.warning("Motion monitoring already active")
            return
        }

        guard motionManager.isAccelerometerAvailable else {
            logger.error("Accelerometer not available on this device")
            return
        }

        logger.info("Starting shake detection monitoring")

        motionManager.startAccelerometerUpdates(to: operationQueue) { [weak self] (data, error) in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Accelerometer error: \(error.localizedDescription)")
                return
            }

            guard let acceleration = data?.acceleration else { return }

            self.processAccelerometerData(acceleration)
        }

        DispatchQueue.main.async {
            self.isMonitoring = true
        }

        logger.info("Shake detection monitoring started")
    }

    /// Stops monitoring for shake gestures
    func stopMonitoring() {
        guard isMonitoring else { return }

        logger.info("Stopping shake detection monitoring")

        motionManager.stopAccelerometerUpdates()

        DispatchQueue.main.async {
            self.isMonitoring = false
        }

        logger.info("Shake detection monitoring stopped")
    }

    // MARK: - Private Methods

    /// Processes accelerometer data to detect shake gestures
    private func processAccelerometerData(_ acceleration: CMAcceleration) {
        // Calculate total acceleration magnitude (g-force)
        let magnitude = sqrt(
            pow(acceleration.x, 2) +
            pow(acceleration.y, 2) +
            pow(acceleration.z, 2)
        )

        // Check if magnitude exceeds threshold
        if magnitude > shakeThreshold {
            // Check cooldown period
            if let lastShake = lastShakeDate {
                let timeSinceLastShake = Date().timeIntervalSince(lastShake)
                if timeSinceLastShake < cooldownPeriod {
                    // Still in cooldown period, ignore this shake
                    return
                }
            }

            // Valid shake detected
            handleShakeDetected(magnitude: magnitude)
        }
    }

    /// Handles shake detection event
    private func handleShakeDetected(magnitude: Double) {
        logger.info("Shake detected! Magnitude: \(String(format: "%.2f", magnitude))g")

        DispatchQueue.main.async {
            self.lastShakeDate = Date()
        }

        // Trigger callback
        onShakeDetected?()
    }

    // MARK: - Deinitialization

    deinit {
        stopMonitoring()
        logger.info("MotionManager deinitialized")
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
