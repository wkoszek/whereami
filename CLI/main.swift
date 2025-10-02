import Foundation
import CoreBluetooth
import Dispatch

@main
enum WhereAmICLI {
    static func main() {
        let client = BLELocationClient()
        let statusPrinter = CLIStatusPrinter()
        client.delegate = statusPrinter

        Task {
            do {
                let sample = try await requestWithRetry(client: client)
                let payload: [String: Any] = [
                    "latitude": sample.latitude,
                    "longitude": sample.longitude,
                    "horizontalAccuracy": sample.horizontalAccuracy,
                    "timestamp": ISO8601DateFormatter().string(from: sample.timestamp)
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                if let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
                fflush(stdout)
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
            fputs("Error: timed out waiting for location\n", stderr)
            exit(1)
        }

        dispatchMain()
    }
}

@MainActor
final class CLIStatusPrinter: BLELocationClientDelegate {
    func locationClient(_ client: BLELocationClient, didUpdateStatus status: String) {
        fputs("[status] \(status)\n", stderr)
    }

    func locationClient(_ client: BLELocationClient, didUpdate sample: LocationSample?) {
        guard let sample else { return }
        let message = String(format: "[sample] lat=%.6f lon=%.6f acc=%.1fm\n", sample.latitude, sample.longitude, sample.horizontalAccuracy)
        fputs(message, stderr)
    }
}

private func requestWithRetry(client: BLELocationClient) async throws -> LocationSample {
    var attempt = 0
    while true {
        do {
            return try await client.requestLocation()
        } catch BLELocationClient.ClientError.bluetoothUnavailable {
            attempt += 1
            fputs("[retry] bluetooth unavailable; waiting for power on (attempt \(attempt))\n", stderr)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch BLELocationClient.ClientError.busy {
            attempt += 1
            fputs("[retry] client busy; retrying\n", stderr)
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            throw error
        }
    }
}
