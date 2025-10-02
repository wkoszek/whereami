#if os(macOS)
import SwiftUI

@MainActor
final class MacLocationViewModel: ObservableObject {
    @Published var status: String = "Ready"
    @Published var lastSample: LocationSample?
    @Published var isRequesting = false
    @Published var errorMessage: String?
    @Published var log: [StatusLog] = []

    private let client: BLELocationClient

    init(client: BLELocationClient = BLELocationClient()) {
        self.client = client
        self.client.delegate = self
    }

    func requestLocation() {
        guard !isRequesting else { return }
        isRequesting = true
        status = "Requesting…"
        log.append(StatusLog(message: "Manual request initiated"))
        Task {
            do {
                let sample = try await client.requestLocation()
                await MainActor.run {
                    self.lastSample = sample
                    self.status = "Latest location received"
                    self.log.append(StatusLog(message: "Received location: \(sample.latitude), \(sample.longitude)"))
                    self.isRequesting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = "Failed"
                    self.log.append(StatusLog(message: "Error: \(error.localizedDescription)"))
                    self.isRequesting = false
                }
            }
        }
    }

    func cancel() {
        client.cancelOutstandingRequest()
        isRequesting = false
        status = "Cancelled"
        log.append(StatusLog(message: "Request cancelled"))
    }
}

extension MacLocationViewModel: BLELocationClientDelegate {
    func locationClient(_ client: BLELocationClient, didUpdateStatus status: String) {
        Task { @MainActor in
            self.status = status
            self.log.append(StatusLog(message: status))
        }
    }

    func locationClient(_ client: BLELocationClient, didUpdate sample: LocationSample?) {
        Task { @MainActor in
            self.lastSample = sample
        }
    }
}
#endif
