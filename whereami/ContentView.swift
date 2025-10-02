import SwiftUI

struct ContentView: View {
    var body: some View {
#if os(iOS)
        PhonePeripheralView()
#elseif os(macOS)
        MacRequesterView()
#else
        Text("Unsupported platform")
#endif
    }
}

#if os(iOS)
private struct PhonePeripheralView: View {
    @StateObject private var coordinator = PhonePeripheralCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("whereami – Phone")
                .font(.title)
                .bold()

            StatusBlock(title: "Status", value: statusText)
            if let location = coordinator.lastSample {
                StatusBlock(title: "Last Shared", value: formatted(location: location))
            }

            Button(action: coordinator.requestAuthorizationIfNeeded) {
                Text("Check Location Permission")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .alert("Share your location?", isPresented: $coordinator.showSharePrompt) {
            Button("Share", role: .none, action: coordinator.approveCurrentRequest)
            Button("Ignore", role: .cancel, action: coordinator.rejectCurrentRequest)
        } message: {
            Text("A paired Mac is requesting a single GPS fix.")
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:
            return "Ready for requests"
        case .preparing:
            return "Preparing service…"
        case .advertising:
            return "Advertising over Bluetooth"
        case .awaitingApproval(_):
            return "Mac is waiting for your confirmation"
        case .acquiringLocation(_):
            return "Acquiring precise location…"
        case .delivered(_):
            return "Latest location shared"
        case .error(let message):
            return message
        }
    }

    private func formatted(location: LocationSample) -> String {
        "Lat: \(location.latitude), Lon: \(location.longitude) ±\(Int(location.horizontalAccuracy))m"
    }
}
#endif

#if os(macOS)
private struct MacRequesterView: View {
    @StateObject private var viewModel = MacLocationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("whereami – Mac")
                .font(.title)
                .bold()

            StatusBlock(title: "Status", value: viewModel.status)
            if let sample = viewModel.lastSample {
                StatusBlock(title: "Last fix", value: formatted(sample: sample))
            }

            HStack {
                Button("Request Location") {
                    viewModel.requestLocation()
                }
                .disabled(viewModel.isRequesting)

                Button("Cancel") {
                    viewModel.cancel()
                }
                .disabled(!viewModel.isRequesting)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
            }

            if !viewModel.log.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.log) { entry in
                            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(entry.message)
                                .font(.footnote)
                                .padding(.bottom, 4)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Spacer()
        }
        .frame(minWidth: 320, minHeight: 220)
        .padding()
    }

    private func formatted(sample: LocationSample) -> String {
        "Lat: \(sample.latitude), Lon: \(sample.longitude) ±\(Int(sample.horizontalAccuracy))m at \(sample.timestamp.formatted(.dateTime.hour().minute().second()))"
    }
}
#endif

private struct StatusBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
