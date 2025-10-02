#if os(iOS)
import Foundation
import CoreBluetooth
import CoreLocation
@MainActor
final class PhonePeripheralCoordinator: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case advertising
        case awaitingApproval(LocationRequest)
        case acquiringLocation(LocationRequest)
        case delivered(LocationSample)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSample: LocationSample?
    @Published var showSharePrompt: Bool = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let peripheralManager: CBPeripheralManager
    private let locationManager: CLLocationManager
    private let requestCharacteristic: CBMutableCharacteristic
    private let responseCharacteristic: CBMutableCharacteristic
    private var currentRequest: LocationRequest?

    override init() {
        let manager = CLLocationManager()
        locationManager = manager
        authorizationStatus = manager.authorizationStatus
        requestCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.requestCharacteristicUUID),
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        responseCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.responseCharacteristicUUID),
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)
        super.init()
        locationManager.delegate = self
        peripheralManager.delegate = self
    }

    nonisolated private func performOnMain(_ action: @escaping @MainActor (PhonePeripheralCoordinator) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                action(self)
            }
        }
    }

    private func log(_ message: String) {
        print("[PhonePeripheral] \(message)")
    }

    func requestAuthorizationIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .error("Location permission denied. Enable it in Settings.")
        default:
            break
        }
    }

    func approveCurrentRequest() {
        guard let request = currentRequest else { return }
        showSharePrompt = false
        status = .acquiringLocation(request)
        startLocationAcquisition()
    }

    func rejectCurrentRequest() {
        showSharePrompt = false
        status = .idle
        currentRequest = nil
    }

    private func prepareService() {
        log("installing BLE service")
        status = .preparing
        let service = CBMutableService(type: CBUUID(string: BLEProtocol.serviceUUID), primary: true)
        service.characteristics = [requestCharacteristic, responseCharacteristic]
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
    }

    private func startAdvertisingIfPossible() {
        guard peripheralManager.state == .poweredOn else { return }
        log("starting advertising")
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEProtocol.serviceUUID)],
            CBAdvertisementDataLocalNameKey: "whereami-phone"
        ])
        if case .preparing = status {
            status = .advertising
        }
    }

    private func startLocationAcquisition() {
        log("startLocationAcquisition invoked")
        requestAuthorizationIfNeeded()
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            log("requesting one-shot location")
            locationManager.requestLocation()
        case .notDetermined:
            // Authorization prompt is in progress; keep waiting.
            log("authorization pending")
            break
        default:
            status = .error("Location permission unavailable.")
            log("location permission unavailable")
            currentRequest = nil
        }
    }

    private func publish(sample: LocationSample) {
        log("publishing sample lat=\(sample.latitude) lon=\(sample.longitude) acc=\(sample.horizontalAccuracy)")
        lastSample = sample
        status = .delivered(sample)
        guard let data = try? LocationWireCodec.encode(sample) else {
            status = .error("Failed to encode location.")
            log("failed to encode location sample")
            return
        }
        responseCharacteristic.value = data
        let success = peripheralManager.updateValue(
            data,
            for: responseCharacteristic,
            onSubscribedCentrals: nil
        )
        if !success {
            status = .error("Unable to update central subscriber.")
            log("failed to push data to central")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self = self else { return }
                if case .delivered = self.status {
                    self.status = .idle
                }
            }
        }
        currentRequest = nil
    }
}

extension PhonePeripheralCoordinator: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        performOnMain { coordinator in
            switch peripheral.state {
            case .poweredOn:
                coordinator.log("peripheral powered on")
                coordinator.prepareService()
                coordinator.startAdvertisingIfPossible()
            case .unauthorized:
                coordinator.status = .error("Bluetooth permission denied")
                coordinator.log("bluetooth unauthorized")
            case .poweredOff:
                coordinator.status = .error("Bluetooth is off")
                coordinator.log("bluetooth off")
            default:
                break
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        performOnMain { coordinator in
            if let error {
                coordinator.status = .error("Service error: \(error.localizedDescription)")
                coordinator.log("service add error: \(error.localizedDescription)")
            } else {
                coordinator.log("service added successfully")
            }
            coordinator.startAdvertisingIfPossible()
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        performOnMain { coordinator in
            if let error {
                coordinator.status = .error("Advertising error: \(error.localizedDescription)")
                coordinator.log("advertising error: \(error.localizedDescription)")
            } else if case .preparing = coordinator.status {
                coordinator.status = .advertising
                coordinator.log("advertising active")
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first,
              let value = first.value,
              let request = try? LocationWireCodec.decodeRequest(from: value) else {
            performOnMain { coordinator in
                coordinator.status = .error("Invalid request")
                coordinator.log("invalid request received")
            }
            return
        }
        performOnMain { coordinator in
            coordinator.currentRequest = request
            coordinator.status = .awaitingApproval(request)
            coordinator.log("received location request \(request.id)")
            coordinator.showSharePrompt = true
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        performOnMain { coordinator in
            if case .advertising = coordinator.status {
                coordinator.status = .idle
                coordinator.log("central subscribed; moving to idle")
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        performOnMain { coordinator in
            guard request.characteristic.uuid == CBUUID(string: BLEProtocol.responseCharacteristicUUID) else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                return
            }
            if let value = coordinator.responseCharacteristic.value {
                request.value = value
                peripheral.respond(to: request, withResult: .success)
                coordinator.log("responded to central read with cached sample")
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
                coordinator.log("read requested before a sample was available")
            }
        }
    }
}

extension PhonePeripheralCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        performOnMain { coordinator in
            coordinator.authorizationStatus = manager.authorizationStatus
            if case .acquiringLocation = coordinator.status {
                coordinator.startLocationAcquisition()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        performOnMain { coordinator in
            coordinator.status = .error("Location error: \(error.localizedDescription)")
            coordinator.log("location error: \(error.localizedDescription)")
            coordinator.currentRequest = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        performOnMain { coordinator in
            guard let location = locations.last else {
                coordinator.status = .error("No location data")
                coordinator.log("location manager returned empty list")
                coordinator.currentRequest = nil
                return
            }
            let sample = LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
            coordinator.publish(sample: sample)
        }
    }
}
#endif
