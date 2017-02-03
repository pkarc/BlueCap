//
//  Service.swift
//  BlueCap
//
//  Created by Troy Stribling on 6/11/14.
//  Copyright (c) 2014 Troy Stribling. The MIT License (MIT).
//

import Foundation
import CoreBluetooth

// MARK: - Service -
public class Service {

    fileprivate var characteristicDiscoverySequence = 0
    fileprivate var characteristicsDiscoveredPromise: Promise<Void>?

    // MARK: Properties

    public let uuid: CBUUID

    public var name: String {
        return profile?.name ?? "Unknown"
    }

    var discoveredCharacteristicsUUIDs = [String]()
    
    public var characteristics: [Characteristic] {
        guard let discoveredCharacteristics = peripheral?.discoveredCharacteristics else {
            return []
        }
        return Array(discoveredCharacteristics.values).filter { self.discoveredCharacteristicsUUIDs.contains($0.uuid.uuidString) }
    }
    
    fileprivate(set) weak var profile: ServiceProfile?
    fileprivate(set) weak var cbService: CBServiceInjectable?
    public fileprivate(set) weak var peripheral: Peripheral?

    var centralQueue: Queue {
        return peripheral!.centralQueue
    }

    // MARK: Initializer

    internal init(cbService: CBServiceInjectable, peripheral: Peripheral, profile: ServiceProfile? = nil) {
        self.cbService = cbService
        self.peripheral = peripheral
        self.profile = profile
        uuid = CBUUID(data: cbService.uuid.data)
    }

    // MARK: Discover Characteristics

    public func discoverAllCharacteristics(timeout: TimeInterval = TimeInterval.infinity) -> Future<Void> {
        Logger.debug("uuid=\(uuid.uuidString), name=\(self.name)")
        return self.discoverIfConnected(nil, timeout: timeout)
    }
    
    public func discoverCharacteristics(_ characteristics: [CBUUID], timeout: TimeInterval = TimeInterval.infinity) -> Future<Void> {
        Logger.debug("uuid=\(uuid.uuidString), name=\(self.name)")
        return self.discoverIfConnected(characteristics, timeout: timeout)
    }
    
    public func characteristic(_ uuid: CBUUID) -> Characteristic? {
        return peripheral?.discoveredCharacteristics[uuid]
    }

    // MARK: CBPeripheralDelegate Shim

    internal func didDiscoverCharacteristics(_ discoveredCharacteristics: [CBCharacteristicInjectable], error: Swift.Error?) {
        guard let peripheral = peripheral else {
            return
        }
        discoveredCharacteristicsUUIDs.removeAll()
        if let error = error {
            Logger.debug("Error discovering \(error), service name \(name), service uuid \(uuid), characteristic count \(discoveredCharacteristics.count)")
            if let characteristicsDiscoveredPromise = self.characteristicsDiscoveredPromise, !characteristicsDiscoveredPromise.completed {
                self.characteristicsDiscoveredPromise?.failure(error)
            }
            for cbCharacteristic in discoveredCharacteristics {
                let bcCharacteristic = Characteristic(cbCharacteristic: cbCharacteristic, service: self)
                Logger.debug("Error discovering characterisc uuid=\(cbCharacteristic.uuid.uuidString), characteristic name=\(bcCharacteristic.name), service name \(name), service uuid \(uuid)")
            }
        } else {
            discoveredCharacteristics.forEach { cbCharacteristic in
                Logger.debug("Discovered characterisc uuid=\(cbCharacteristic.uuid.uuidString), service name \(name), service uuid \(uuid)")
                peripheral.discoveredCharacteristics[cbCharacteristic.uuid] = Characteristic(cbCharacteristic: cbCharacteristic, service: self)
                discoveredCharacteristicsUUIDs.append(cbCharacteristic.uuid.uuidString)
            }
            Logger.debug("discovery success service name \(name), service uuid \(uuid)")
            if let characteristicsDiscoveredPromise = characteristicsDiscoveredPromise, !characteristicsDiscoveredPromise.completed {
                characteristicsDiscoveredPromise.success()
            }
        }
    }

    internal func didDisconnectPeripheral(_ error: Swift.Error?) {
        if let characteristicsDiscoveredPromise = self.characteristicsDiscoveredPromise, !characteristicsDiscoveredPromise.completed {
            characteristicsDiscoveredPromise.failure(PeripheralError.disconnected)
        }
    }

    // MARK: Utils

    fileprivate func discoverIfConnected(_ characteristics: [CBUUID]?, timeout: TimeInterval) -> Future<Void> {
        if let characteristicsDiscoveredPromise = self.characteristicsDiscoveredPromise, !characteristicsDiscoveredPromise.completed {
            return characteristicsDiscoveredPromise.future
        }
        guard let peripheral = peripheral, let cbService = cbService else {
            return Future<Void>(error: ServiceError.unconfigured)
        }
        if peripheral.state == .connected {
            characteristicsDiscoveredPromise = Promise<Void>()
            characteristicDiscoverySequence += 1
            timeoutCharacteristicDiscovery(self.characteristicDiscoverySequence, timeout: timeout)
            peripheral.discoverCharacteristics(characteristics, forService: cbService)
            return self.characteristicsDiscoveredPromise!.future
        } else {
            return Future<Void>(error: PeripheralError.disconnected)
        }
    }

    fileprivate func timeoutCharacteristicDiscovery(_ sequence: Int, timeout: TimeInterval) {
        guard let peripheral = peripheral, timeout < TimeInterval.infinity, cbService != nil else {
            return
        }
        Logger.debug("name = \(self.name), uuid = \(peripheral.identifier.uuidString), sequence = \(sequence), timeout = \(timeout)")
        centralQueue.delay(timeout) { [weak self, weak peripheral] in
            self.forEach { strongSelf in
                if let characteristicsDiscoveredPromise = strongSelf.characteristicsDiscoveredPromise, sequence == strongSelf.characteristicDiscoverySequence && !characteristicsDiscoveredPromise.completed {
                    Logger.debug("characteristic scan timing out name = \(strongSelf.name), peripheral uuid = \(peripheral?.identifier.uuidString), sequence=\(sequence), current sequence = \(strongSelf.characteristicDiscoverySequence)")
                    characteristicsDiscoveredPromise.failure(ServiceError.characteristicDiscoveryTimeout)
                } else {
                    Logger.debug("characteristic scan timeout expired name = \(strongSelf.name), peripheral UUID = \(peripheral?.identifier.uuidString), sequence = \(sequence), current sequence = \(strongSelf.characteristicDiscoverySequence)")
                }
            }
        }
    }

}
