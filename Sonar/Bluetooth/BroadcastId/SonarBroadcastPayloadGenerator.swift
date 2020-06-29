//
//  ConcreteBroadcastIdGenerator.swift
//  Sonar
//
//  Created by NHSX on 10/04/2020.
//  Copyright © 2020 NHSX. All rights reserved.
//

import Foundation
import Logging

protocol BroadcastPayloadGenerator
{
    func broadcastPayload(date: Date) -> BroadcastPayload?
}

extension BroadcastPayloadGenerator
{
    func broadcastPayload(date: Date = Date()) -> BroadcastPayload?
    {
        return broadcastPayload(date: date)
    }
}

class SonarBroadcastPayloadGenerator: BroadcastPayloadGenerator
{
    let storage: BroadcastRotationKeyStorage
    let persistence: Persisting
    let provider: BroadcastIdEncrypterProvider

    init(storage: BroadcastRotationKeyStorage, persistence: Persisting, provider: BroadcastIdEncrypterProvider)
    {
        self.storage = storage
        self.persistence = persistence
        self.provider = provider
    }

    func broadcastPayload(date: Date) -> BroadcastPayload?
    {
//        guard let registration = persistence.registration else { return nil }
//
//        let hmacKey = registration.secretKey
        let hmacKey = "80070713463e7749b90c2dc24911e275".data(using: .utf8)    // JT 20.06.17

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        if let (broadcastId, broadcastIdDate) = storage.readBroadcastId(), calendar.isDateInToday(broadcastIdDate)
        {
            return BroadcastPayload(cryptogram: broadcastId, hmacKey: hmacKey!)
        }

        let midnightUTC = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date)!)

        if let broadcastId = provider.getEncrypter()?.broadcastId(from: date, until: midnightUTC)
        {
            storage.save(broadcastId: broadcastId, date: date)
            return BroadcastPayload(cryptogram: broadcastId, hmacKey: hmacKey!) // JT 20.06.17
        }
        else
        {
            return nil
        }
    }
}

private let logger = Logger(label: "BTLE")
