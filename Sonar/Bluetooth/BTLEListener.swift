//
//  BTLEListener.swift
//  Sonar
//
//  Created by NHSX on 12.03.20.
//  Copyright © 2020 NHSX. All rights reserved.
//

import CoreBluetooth
import Logging
import UIKit
//import NSLogger // JT 20.06.27

protocol BTLEPeripheral
{
    var identifier: UUID { get }
}

extension CBPeripheral: BTLEPeripheral
{}

protocol BTLEListenerDelegate
{
    func btleListener(_ listener: BTLEListener, didFind broadcastPayload: IncomingBroadcastPayload, for peripheral: BTLEPeripheral)
    func btleListener(_ listener: BTLEListener, didReadRSSI RSSI: Int, for peripheral: BTLEPeripheral)
    func btleListener(_ listener: BTLEListener, didReadTxPower txPower: Int, for peripheral: BTLEPeripheral)
}

protocol BTLEListenerStateDelegate
{
    func btleListener(_ listener: BTLEListener, didUpdateState state: CBManagerState)
}

protocol BTLEListener
{
    func start(stateDelegate: BTLEListenerStateDelegate?, delegate: BTLEListenerDelegate?)
    func isHealthy() -> Bool
}

class ConcreteBTLEListener: NSObject, BTLEListener, CBCentralManagerDelegate, CBPeripheralDelegate
{
    var broadcaster: BTLEBroadcaster // just for keepalive  // JT 20.06.20
    var stateDelegate: BTLEListenerStateDelegate?
    var delegate: BTLEListenerDelegate?

    var peripherals: [UUID: CBPeripheral] = [:]

    // comfortably less than the ~10s background processing time Core Bluetooth gives us when it wakes us up
    private let keepaliveInterval: TimeInterval = 8.0

    private var lastKeepaliveDate: Date = Date.distantPast
    private var keepaliveValue: UInt8 = 0
    private var keepaliveTimer: DispatchSourceTimer?
    private let dateFormatter = ISO8601DateFormatter()
    private let queue: DispatchQueue

    init(broadcaster: BTLEBroadcaster, queue: DispatchQueue)
    {
        self.broadcaster = broadcaster
        self.queue = queue
        



    }

    @objc func applicationDidBecomeActive() {
        // handle event
        Swift.print("applicationDidBecomeActive")
    //   logger.info("🔷🔷 central \(broadcaster.central.isScanning ? "is" : "is not") scanning") // JT 20.06.28

    }
    
    func start(stateDelegate: BTLEListenerStateDelegate?, delegate: BTLEListenerDelegate?)
    {
        self.stateDelegate = stateDelegate
        self.delegate = delegate
        
        //  adding observer

          NotificationCenter.default.addObserver(self,
              selector: #selector(applicationDidBecomeActive),
              name: UIApplication.didBecomeActiveNotification,
              object: nil)  // JT 20.06.28
        
    }

    // MARK: CBCentralManagerDelegate

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    {
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
        {
            logger.info("⬛ restoring \(restoredPeripherals.count) \(restoredPeripherals.count == 1 ? "peripheral" : "peripherals") for central \(central)")
            for peripheral in restoredPeripherals
            {
                Swift.print("⬛⬛ peripheral.identifier \(peripheral.identifier)")   // JT 20.06.28
                peripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
        }
        else
        {
            logger.info("no peripherals to restore for \(central)")
        }

        if let restoredScanningServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID]
        {
            logger.info("🔷 restoring scanning for \(restoredScanningServices.count) \(restoredScanningServices.count == 1 ? "service" : "services") for central \(central)")
            for restoredScanningService in restoredScanningServices
            {
                logger.info(" 🔷 restoredScanningService   service \(restoredScanningService.uuidString)")
            }
        }
        else
        {
            logger.info("no scanning restored for \(central)")
        }

        if let scanOptions = dict[CBCentralManagerRestoredStateScanOptionsKey] as? [String: Any]
        {
            logger.info("🔷 restoring \(scanOptions.count) \(scanOptions.count == 1 ? "scanOption" : "scanOptions") for central \(central)")
            for scanOption in scanOptions
            {
                logger.info(" 🔷   scanOption: \(scanOption.key), value: \(scanOption.value)")
            }
        }
        else
        {
            logger.info("no scanOptions restored for \(central)")
        }
        logger.info("🔷🔷 central \(central.isScanning ? "is" : "is not") scanning")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        logger.info("🔷 state: \(central.state)")

        stateDelegate?.btleListener(self, didUpdateState: central.state)

        switch central.state
        {
        case .poweredOn:

            // Reconnect to all the peripherals we found in willRestoreState (assume calling connect is idempotent)
            for peripheral in peripherals.values
            {
                Swift.print("🔷 centralManagerDidUpdateState poweredOn connect \(peripheral)")    // JT 20.06.26
                central.connect(peripheral)
            }

            Swift.print("🔷 poweredOn scanForPeripherals \(Environment.sonarServiceUUID) ")  // JT 20.06.28
            
            central.scanForPeripherals(withServices: [Environment.sonarServiceUUID])

        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        if let txPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        {            
            logger.info("💜 didDiscover peripheral \(peripheral.identifierWithName) discovered with RSSI = \(RSSI), txPower = \(txPower)")
            delegate?.btleListener(self, didReadTxPower: txPower, for: peripheral)
            Swift.print("💜 \(advertisementData)") // JT 20.06.28
        }
        else
        {
            logger.info("peripheral \(peripheral.identifierWithName) discovered with RSSI = \(RSSI)")
        }

        if peripherals[peripheral.identifier] == nil || peripherals[peripheral.identifier]!.state != .connected
        {
            peripherals[peripheral.identifier] = peripheral
            central.connect(peripheral)
            
            Swift.print("🔷 central.connect(peripheral) \(peripheral)")  // JT 20.06.28
        }
        else
        {
            Swift.print("🔷🔷 already connected to \(peripheral)")  // JT 20.06.28
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        logger.info("✅✅ didConnect \(peripheral.identifierWithName)")  // JT 20.06.26

        peripheral.delegate = self
        peripheral.readRSSI()
        peripheral.discoverServices([Environment.sonarServiceUUID])
    }
//(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error;
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)  // JT 20.06.28
     {
        logger.info("🔴 didFailToConnectPeripheral \(peripheral.identifierWithName) \(String(describing: error))") // JT 20.06.28
        Swift.print("")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        Swift.print("🌕🌕 didDisconnectPeripheral")  // JT 20.06.26
        
        if let error = error
        {
            logger.info("🔘 attempting reconnection to \(peripheral.identifierWithName) after error: \(error)")
        }
        else
        {
            logger.info("🔷 attempting reconnection to \(peripheral.identifierWithName)")
        }
        central.connect(peripheral)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    {
        logger.info("🔷 \(peripheral.identifierWithName) invalidatedServices:")
        for service in invalidatedServices
        {
            logger.info("🔷 \t\(service)\n")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        guard error == nil else
        {
            logger.info("❌ peripheral \(peripheral.identifierWithName) error: \(error!)")
            return
        }

        guard let services = peripheral.services, services.count > 0 else
        {
            logger.info("❌ No services discovered for peripheral \(peripheral.identifierWithName)")
            return
        }

        guard let sonarIdService = services.sonarIdService() else
        {
            logger.info("❌ sonarId service not discovered for \(peripheral.identifierWithName)")
            return
        }

        logger.info("🔷 discovering characteristics for peripheral \(peripheral.identifierWithName) with sonarId service\n \(sonarIdService)\n")
        let characteristics = [
            Environment.sonarIdCharacteristicUUID,
            Environment.keepaliveCharacteristicUUID,
        ]
        peripheral.discoverCharacteristics(characteristics, for: sonarIdService)
        
        Swift.print("🔷 discoverCharacteristics \(characteristics)")    // JT 20.06.28
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        guard error == nil else
        {
            logger.info("❌ periperhal \(peripheral.identifierWithName) error: \(error!)")
            return
        }

        guard let characteristics = service.characteristics, characteristics.count > 0 else
        {
            logger.info("❌ no characteristics discovered for service \(service)")
            return
        }
        logger.info("✅ \(characteristics.count) \(characteristics.count == 1 ? "characteristic" : "characteristics") discovered for service \(service): \(characteristics)")

        if let sonarIdCharacteristic = characteristics.sonarIdCharacteristic()
        {
            logger.info("🔷 reading sonarId from sonarId characteristic \(sonarIdCharacteristic)")
            peripheral.readValue(for: sonarIdCharacteristic)
            peripheral.setNotifyValue(true, for: sonarIdCharacteristic)
        }
        else
        {
            logger.info("❌ sonarId characteristic not discovered for peripheral \(peripheral.identifierWithName)")
        }

        if let keepaliveCharacteristic = characteristics.keepaliveCharacteristic()
        {
            logger.info("💜 subscribing to keepalive characteristic \(keepaliveCharacteristic)")
            peripheral.setNotifyValue(true, for: keepaliveCharacteristic)
        }
        else
        {
            logger.info("❌ keepalive characteristic not discovered for peripheral \(peripheral.identifierWithName)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        Swift.print("🔷 didUpdateValueFor \(characteristic)")
        guard error == nil else
        {
            logger.info("❌ characteristic \(characteristic) error: \(error!)")
            return
        }

        switch characteristic.value
        {
        case let data? where characteristic.uuid == Environment.sonarIdCharacteristicUUID:
            if data.count == BroadcastPayload.length
            {
                logger.info("🔷 read identity from peripheral \(peripheral.identifierWithName): \(data)")
                delegate?.btleListener(self, didFind: IncomingBroadcastPayload(data: data), for: peripheral)
            }
            else
            {
                logger.info("🔶 data.count \(data.count)\n no identity ready from peripheral \(peripheral.identifierWithName)")
            }
            peripheral.readRSSI()

        case let data? where characteristic.uuid == Environment.keepaliveCharacteristicUUID:
            guard data.count == 1 else
            {
                logger.info("❌ invalid keepalive value \(data)")
                return
            }

            let keepaliveValue = data.withUnsafeBytes { $0.load(as: UInt8.self) }
            logger.info("💜 read keepalive value from peripheral \(peripheral.identifierWithName): \(keepaliveValue)")
            readRSSIAndSendKeepalive()

        case .none:
            logger.info("❌ characteristic \(characteristic) has no data")

        default:
            logger.info("❌ characteristic \(characteristic) has unknown uuid \(characteristic.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)
    {
        guard error == nil else
        {
            logger.info("❌ error: \(error!)")
            return
        }

        logger.info("🔷 read RSSI for \(peripheral.identifierWithName): \(RSSI)")
        delegate?.btleListener(self, didReadRSSI: RSSI.intValue, for: peripheral)
        readRSSIAndSendKeepalive()
    }

    private func readRSSIAndSendKeepalive()
    {
        guard Date().timeIntervalSince(lastKeepaliveDate) > keepaliveInterval else
        {
            logger.info("🌗 too soon, won't send keepalive (lastKeepalive = \(lastKeepaliveDate))")  // JT 20.06.25
            return
        }

        logger.info("🔷 reading RSSI for \(peripherals.values.count) \(peripherals.values.count == 1 ? "peripheral" : "peripherals")")
        for peripheral in peripherals.values
        {
            peripheral.readRSSI()
        }

        logger.info("⚫️ scheduling keepalive")  // JT 20.06.28
        lastKeepaliveDate = Date()
        keepaliveValue = keepaliveValue &+ 1 // note "&+" overflowing add operator, this is required
        let value = Data(bytes: &keepaliveValue, count: MemoryLayout.size(ofValue: keepaliveValue))
        keepaliveTimer = DispatchSource.makeTimerSource(queue: queue)
        keepaliveTimer?.setEventHandler
        {
            self.broadcaster.sendKeepalive(value: value)
        }
        keepaliveTimer?.schedule(deadline: DispatchTime.now() + keepaliveInterval)
        keepaliveTimer?.resume()
    }

    func isHealthy() -> Bool
    {
        guard keepaliveTimer != nil else { return false }
        guard stateDelegate != nil else { return false }
        guard delegate != nil else { return false }

        return true
    }

    fileprivate let logger = Logger(label: "BTLE")
}
