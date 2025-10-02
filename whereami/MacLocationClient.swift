#if os(macOS)
import Foundation
import CoreBluetooth

@MainActor
protocol BLELocationClientDelegate: AnyObject {
    func locationClient(_ client: BLELocationClient, didUpdateStatus status: String)
    func locationClient(_ client: BLELocationClient, didUpdate sample: LocationSample?)
}

/// CoreBluetooth central responsible for talking to the phone peripheral.
/// UI and CLI layers can drive it by calling `requestLocation()`.
final class BLELocationClient: NSObject {
    enum ClientError: Error, LocalizedError {
        case bluetoothUnavailable
        case busy
        case peripheralUnavailable
        case characteristicMissing
        case cancelled
        case decodeFailed
        case timeout

        var errorDescription: String? {
            switch self {
            case .bluetoothUnavailable:
                return "Bluetooth is unavailable or turned off."
            case .busy:
                return "A location request is already in progress."
            case .peripheralUnavailable:
                return "Could not find the phone peripheral."
            case .characteristicMissing:
                return "Expected BLE characteristics were not found."
            case .cancelled:
                return "Request was cancelled."
            case .decodeFailed:
                return "Failed to decode the location payload."
            case .timeout:
                return "Timed out waiting for location response."
            }
        }
    }

    weak var delegate: BLELocationClientDelegate?

    private let central: CBCentralManager
    private var targetPeripheral: CBPeripheral?
    private var requestCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var pendingContinuation: CheckedContinuation<LocationSample, Error>?
    private var pendingRequest: LocationRequest?
    private var responseTimer: Timer?

    override init() {
        central = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        central.delegate = self
    }

    private func sendStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.locationClient(self, didUpdateStatus: status)
        }
    }

    private func sendSample(_ sample: LocationSample?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.locationClient(self, didUpdate: sample)
        }
    }

    private func log(_ message: String) {
        print("[BLELocationClient] \(message)")
    }

    func requestLocation() async throws -> LocationSample {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard self.pendingContinuation == nil else {
                    self.log("request rejected: busy")
                    continuation.resume(throwing: ClientError.busy)
                    return
                }
                guard self.central.state == .poweredOn else {
                    self.log("request rejected: bluetooth unavailable")
                    continuation.resume(throwing: ClientError.bluetoothUnavailable)
                    return
                }
                self.log("request started")
                self.pendingContinuation = continuation
                self.performRequest()
            }
        }
    }

    func cancelOutstandingRequest() {
        log("cancel requested")
        responseTimer?.invalidate()
        responseTimer = nil
        if let continuation = pendingContinuation {
            continuation.resume(throwing: ClientError.cancelled)
            pendingContinuation = nil
        }
        pendingRequest = nil
    }

    private func performRequest() {
        log("performRequest invoked")
        sendStatus("Searching for phone…")
        if let peripheral = targetPeripheral, peripheral.state == .connected, let requestCharacteristic {
            log("peripheral already connected; writing request")
            writeRequest(on: peripheral, characteristic: requestCharacteristic)
        } else {
            startScanning()
        }
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        log("starting scan")
        central.stopScan()
        central.scanForPeripherals(withServices: [CBUUID(string: BLEProtocol.serviceUUID)], options: nil)
        sendStatus("Scanning…")
    }

    private func writeRequest(on peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        log("writing request to \(peripheral.identifier.uuidString)")
        let request = LocationRequest()
        pendingRequest = request
        guard let data = try? LocationWireCodec.encode(request) else {
            log("failed to encode request payload")
            fail(with: ClientError.characteristicMissing)
            return
        }
        sendStatus("Requesting location…")
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        startResponseTimer()
        if let responseCharacteristic {
            log("issuing fallback read for response characteristic")
            peripheral.readValue(for: responseCharacteristic)
        }
    }

    private func startResponseTimer() {
        responseTimer?.invalidate()
        log("arming response timer")
        responseTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.log("request timed out")
            self.fail(with: ClientError.timeout)
        }
    }

    private func deliver(sample: LocationSample) {
        log("got location lat=\(sample.latitude) lon=\(sample.longitude) acc=\(sample.horizontalAccuracy)")
        responseTimer?.invalidate()
        responseTimer = nil
        sendStatus("Received location")
        sendSample(sample)
        pendingRequest = nil
        if let continuation = pendingContinuation {
            continuation.resume(returning: sample)
            pendingContinuation = nil
        }
    }

    private func fail(with error: Error) {
        log("request failed: \(error.localizedDescription)")
        responseTimer?.invalidate()
        responseTimer = nil
        sendStatus("Error: \(error.localizedDescription)")
        sendSample(nil)
        if let continuation = pendingContinuation {
            continuation.resume(throwing: error)
            pendingContinuation = nil
        }
        pendingRequest = nil
    }
}

extension BLELocationClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("central powered on")
            sendStatus("Bluetooth ready")
        case .unauthorized, .poweredOff:
            log("central unavailable: \(central.state.rawValue)")
            sendStatus("Bluetooth unavailable")
            cancelOutstandingRequest()
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log("discovered peripheral \(peripheral.identifier.uuidString) rssi=\(RSSI)")
        sendStatus("Discovered \(peripheral.name ?? "phone")")
        central.stopScan()
        targetPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected to \(peripheral.identifier.uuidString)")
        sendStatus("Connected; discovering services…")
        peripheral.discoverServices([CBUUID(string: BLEProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("failed to connect: \(error?.localizedDescription ?? "unknown error")")
        fail(with: error ?? ClientError.peripheralUnavailable)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("disconnected from peripheral (error=\(error?.localizedDescription ?? "none"))")
        sendStatus("Disconnected")
        if let error {
            fail(with: error)
        } else {
            requestCharacteristic = nil
            responseCharacteristic = nil
            if pendingContinuation != nil {
                startScanning()
            }
        }
    }
}

extension BLELocationClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("service discovery failed: \(error.localizedDescription)")
            fail(with: error)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: BLEProtocol.serviceUUID) }) else {
            log("expected service missing")
            fail(with: ClientError.peripheralUnavailable)
            return
        }
        log("service discovered; discovering characteristics")
        peripheral.discoverCharacteristics([
            CBUUID(string: BLEProtocol.requestCharacteristicUUID),
            CBUUID(string: BLEProtocol.responseCharacteristicUUID)
        ], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            log("characteristic discovery failed: \(error.localizedDescription)")
            fail(with: error)
            return
        }
        requestCharacteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BLEProtocol.requestCharacteristicUUID) })
        responseCharacteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BLEProtocol.responseCharacteristicUUID) })

        guard let requestCharacteristic, let responseCharacteristic else {
            log("characteristics missing")
            fail(with: ClientError.characteristicMissing)
            return
        }
        log("subscribing to response notifications")
        peripheral.setNotifyValue(true, for: responseCharacteristic)
        writeRequest(on: peripheral, characteristic: requestCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("notify state update failed: \(error.localizedDescription)")
            fail(with: error)
        } else {
            log("notify state changed isNotifying=\(characteristic.isNotifying)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            if let attError = error as? CBATTError, attError.code == .unlikelyError {
                log("value update reported unlikelyError; waiting for next payload")
                return
            }
            log("value update failed: \(error.localizedDescription)")
            fail(with: error)
            return
        }
        guard characteristic.uuid == CBUUID(string: BLEProtocol.responseCharacteristicUUID), let data = characteristic.value else {
            return
        }
        log("received \(data.count) bytes from peripheral")
        guard let sample = try? LocationWireCodec.decodeSample(from: data) else {
            log("failed to decode sample payload")
            fail(with: ClientError.decodeFailed)
            return
        }
        deliver(sample: sample)
    }
}

extension BLELocationClient: @unchecked Sendable {}
#endif
