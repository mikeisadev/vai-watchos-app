//
//  ContentView.swift
//  vai-watchos-app Watch App
//
//  Created by Michele Mincone on 22/10/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var alertService = AlertService()
    @State private var showError: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: iconForStatus)
                        .font(.system(size: 40))
                        .foregroundColor(colorForStatus)
                        .symbolEffect(.bounce, value: alertService.status)

                    Text("VAI WEARSENSE")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.top, 8)

                // Status Display
                VStack(spacing: 8) {
                    Text(alertService.status.displayText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if alertService.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)

                            Text("Active")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Main Action Button
                Button(action: {
                    alertService.toggleMonitoring()
                }) {
                    Label(
                        alertService.isActive ? "Stop" : "Start",
                        systemImage: alertService.isActive ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(alertService.isActive ? .red : .green)

                // Stats
                if alertService.alertCount > 0 {
                    Divider()
                        .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Alerts Sent:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(alertService.alertCount)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }

                        if let lastAlert = alertService.lastAlertDate {
                            HStack {
                                Text("Last Alert:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastAlert, style: .relative)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                // Instructions
                if !alertService.isActive {
                    Divider()
                        .padding(.vertical, 4)

                    Text("Shake your watch to send an alert with your location")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding()
        }
        .alert("Error", isPresented: $showError, presenting: alertService.error) { _ in
            Button("OK") {
                alertService.error = nil
            }
        } message: { error in
            Text(error.displayMessage)
        }
        .onChange(of: alertService.error) { _, newError in
            showError = newError != nil
        }
    }

    // MARK: - Computed Properties

    private var iconForStatus: String {
        switch alertService.status {
        case .idle:
            return "hand.raised.fill"
        case .monitoring:
            return "antenna.radiowaves.left.and.right"
        case .processingAlert:
            return "location.fill"
        case .sendingAlert:
            return "paperplane.fill"
        case .alertSent:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var colorForStatus: Color {
        switch alertService.status {
        case .idle:
            return .gray
        case .monitoring:
            return .blue
        case .processingAlert:
            return .orange
        case .sendingAlert:
            return .purple
        case .alertSent:
            return .green
        case .error:
            return .red
        }
    }
}

#Preview {
    ContentView()
}
