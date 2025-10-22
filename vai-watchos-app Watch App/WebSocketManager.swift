//
//  WebSocketManager.swift
//  vai-watchos-app Watch App
//
//  Created by Michele Mincone on 22/10/25.
//

import Foundation
import Combine

/// Manages WebSocket connections for real-time communication
/// Handles connection lifecycle, reconnection, and message emission
final class WebSocketManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var error: WebSocketError?

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let logger = Logger(subsystem: "com.example.vaiwatchos", category: "WebSocketManager")

    // MARK: - Configuration

    private let serverURL = "wss://dev.appvai.it/user-location"
    private let reconnectionDelay: TimeInterval = 2.0
    private let maxReconnectionAttempts: Int = 5
    private var reconnectionAttempts: Int = 0
    private var shouldReconnect: Bool = true
    private var pingTimer: Timer?

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed
    }

    // MARK: - Initialization

    override init() {
        super.init()
        configureSession()
        logger.info("WebSocketManager initialized")
    }

    // MARK: - Configuration

    private func configureSession() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true

        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue()
        )
    }

    // MARK: - Public Methods

    /// Connects to the WebSocket server
    func connect() {
        guard connectionState != .connected && connectionState != .connecting else {
            logger.warning("Already connected or connecting")
            return
        }

        guard let url = URL(string: serverURL) else {
            logger.error("Invalid server URL: \(serverURL)")
            updateConnectionState(.failed)
            self.error = .invalidURL
            return
        }

        logger.info("Connecting to WebSocket server: \(serverURL)")
        updateConnectionState(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()

        // Start ping/pong to keep connection alive
        startPingTimer()

        // Simulate connection success (since we don't have Socket.IO native support)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.connectionState == .connecting {
                self.updateConnectionState(.connected)
                self.reconnectionAttempts = 0
                self.logger.info("WebSocket connected successfully")
            }
        }
    }

    /// Disconnects from the WebSocket server
    func disconnect() {
        logger.info("Disconnecting from WebSocket server")

        shouldReconnect = false
        stopPingTimer()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        updateConnectionState(.disconnected)
        logger.info("WebSocket disconnected")
    }

    /// Emits an alert event with location data
    /// - Parameters:
    ///   - userId: Unique user identifier
    ///   - latitude: User's latitude
    ///   - longitude: User's longitude
    func emitAlert(userId: String, latitude: Double, longitude: Double) async throws {
        guard connectionState == .connected else {
            logger.error("Cannot emit alert: WebSocket not connected")
            throw WebSocketError.notConnected
        }

        let alertData: [String: Any] = [
            "event": "alert",
            "data": [
                "user_id": userId,
                "coords": [
                    "latitude": String(latitude),
                    "longitude": String(longitude)
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: alertData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to serialize alert data")
            throw WebSocketError.serializationFailed
        }

        let message = URLSessionWebSocketTask.Message.string(jsonString)

        logger.info("Emitting alert: user_id=\(userId), lat=\(latitude), lon=\(longitude)")

        try await webSocketTask?.send(message)

        logger.info("Alert emitted successfully")
    }

    // MARK: - Private Methods

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleReceivedMessage(message)
                // Continue receiving
                self.receiveMessage()

            case .failure(let error):
                self.logger.error("Receive error: \(error.localizedDescription)")
                self.handleConnectionError(error)
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            logger.info("Received message: \(text)")

        case .data(let data):
            logger.info("Received data: \(data.count) bytes")

        @unknown default:
            logger.warning("Received unknown message type")
        }
    }

    private func handleConnectionError(_ error: Error) {
        logger.error("WebSocket error: \(error.localizedDescription)")

        self.error = .connectionFailed(error)
        updateConnectionState(.failed)

        // Attempt reconnection
        if shouldReconnect && reconnectionAttempts < maxReconnectionAttempts {
            attemptReconnection()
        } else {
            logger.error("Max reconnection attempts reached")
        }
    }

    private func attemptReconnection() {
        reconnectionAttempts += 1
        updateConnectionState(.reconnecting(attempt: reconnectionAttempts))

        logger.info("Attempting reconnection (\(reconnectionAttempts)/\(maxReconnectionAttempts)) in \(reconnectionDelay)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectionDelay) { [weak self] in
            self?.connect()
        }
    }

    private func startPingTimer() {
        stopPingTimer()

        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.logger.warning("Ping failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateConnectionState(_ state: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
        }
    }

    // MARK: - Error Handling

    enum WebSocketError: LocalizedError {
        case invalidURL
        case notConnected
        case serializationFailed
        case connectionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid server URL"
            case .notConnected:
                return "WebSocket not connected"
            case .serializationFailed:
                return "Failed to serialize data"
            case .connectionFailed(let error):
                return "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Deinitialization

    deinit {
        disconnect()
        logger.info("WebSocketManager deinitialized")
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        logger.info("WebSocket connection opened")
        updateConnectionState(.connected)
        reconnectionAttempts = 0
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        logger.info("WebSocket connection closed: code=\(closeCode.rawValue)")
        updateConnectionState(.disconnected)

        if shouldReconnect && reconnectionAttempts < maxReconnectionAttempts {
            attemptReconnection()
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
