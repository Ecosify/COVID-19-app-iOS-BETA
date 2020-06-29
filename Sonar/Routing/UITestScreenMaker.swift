//
//  UITestScreenMaker.swift
//  Sonar
//
//  Created by NHSX on 06/04/2020.
//  Copyright © 2020 NHSX. All rights reserved.
//

#if DEBUG

    import CoreBluetooth
    import UIKit

    struct UITestScreenMaker: ScreenMaking
    {
        func makeViewController(for screen: Screen) -> UIViewController
        {
            switch screen
            {
            case .onboarding:
                let onboardingViewController = OnboardingViewController.instantiate
                { viewController in
                    let env = OnboardingEnvironment(mockWithHost: viewController)
                    let bluetoothNursery = NoOpBluetoothNursery()
                    let coordinator = OnboardingCoordinator(persistence: env.persistence,
                                                            authorizationManager: env.authorizationManager,
                                                            bluetoothNursery: bluetoothNursery)
                    viewController.inject(env: env, coordinator: coordinator, bluetoothNursery: bluetoothNursery, uiQueue: DispatchQueue.main) {}
                }

                return onboardingViewController

            case .status:
                let statusViewController = StatusViewController.instantiate
                { viewController in
                    let persistence = InMemoryPersistence()
                    viewController.inject(persistence: persistence,
                                          registrationService: MockRegistrationService(),
                                          contactEventsUploader: MockContactEventsUploading(),
                                          notificationCenter: NotificationCenter(),
                                          linkingIdManager: MockLinkingIdManager(),
                                          statusProvider: StatusProvider(persisting: persistence),
                                          localeProvider: FixedLocaleProvider())
                }

                return statusViewController
            }
        }
    }

    private extension OnboardingEnvironment
    {
        convenience init(mockWithHost host: UIViewController)
        {
            // TODO: Fix initial state of mocks.
            // Currently it’s set so that onboarding is “done” as soon as we allow data sharing – so we can have a minimal
            // UI test.
            let authorizationManager = EphemeralAuthorizationManager()
            let notificationCenter = NotificationCenter()
            let dispatcher = RemoteNotificationDispatcher(notificationCenter: notificationCenter, userNotificationCenter: UNUserNotificationCenter.current())

            self.init(
                persistence: InMemoryPersistence(),
                authorizationManager: authorizationManager,
                remoteNotificationManager: EphemeralRemoteNotificationManager(host: host, authorizationManager: authorizationManager, dispatcher: dispatcher),
                notificationCenter: notificationCenter
            )
        }
    }

    private class InMemoryPersistence: Persisting
    {
        var delegate: PersistenceDelegate?

        var registration: Registration?
        var potentiallyExposed: Date?
        var selfDiagnosis: SelfDiagnosis?
        var partialPostcode: String?
        var bluetoothPermissionRequested: Bool = false
        var uploadLog: [UploadLog] = []
        var linkingId: LinkingId?
        var lastInstalledVersion: String?
        var lastInstalledBuildNumber: String?
        var acknowledgmentUrls: Set<URL> = []

        func clear()
        {
            registration = nil
            potentiallyExposed = nil
            selfDiagnosis = nil
            partialPostcode = nil
            uploadLog = []
            linkingId = nil
            lastInstalledVersion = nil
            lastInstalledBuildNumber = nil
            acknowledgmentUrls = []
        }
    }

    private class MockRegistrationService: RegistrationService
    {
        var registerCalled = false

        func register()
        {
            registerCalled = true
        }
    }

    private class MockContactEventsUploading: ContactEventsUploading
    {
        var sessionDelegate: ContactEventsUploaderSessionDelegate = ContactEventsUploaderSessionDelegate(validator: MockTrustValidating())

        func upload() throws {}
        func cleanup() {}
        func error(_: Swift.Error) {}
        func ensureUploading() throws {}
    }

    private class MockTrustValidating: TrustValidating
    {
        func canAccept(_: SecTrust?) -> Bool
        {
            return true
        }
    }

    private class FixedLocaleProvider: LocaleProvider
    {
        var locale: Locale = Locale(identifier: "en")
    }

    private class MockLinkingIdManager: LinkingIdManaging
    {
        func fetchLinkingId(completion _: @escaping (LinkingId?) -> Void)
        {}
    }

    private class EphemeralAuthorizationManager: AuthorizationManaging
    {
        var notificationsStatus = NotificationAuthorizationStatus.notDetermined
        var bluetooth: BluetoothAuthorizationStatus = .allowed

        func waitForDeterminedBluetoothAuthorizationStatus(completion: @escaping (BluetoothAuthorizationStatus) -> Void)
        {
            completion(BluetoothAuthorizationStatus.allowed)
        }

        func notifications(completion: @escaping (NotificationAuthorizationStatus) -> Void)
        {
            completion(notificationsStatus)
        }
    }

    private class EphemeralRemoteNotificationManager: RemoteNotificationManager
    {
        let dispatcher: RemoteNotificationDispatching
        private let authorizationManager: EphemeralAuthorizationManager
        private weak var host: UIViewController?

        var pushToken: String?

        init(host: UIViewController, authorizationManager: EphemeralAuthorizationManager, dispatcher: RemoteNotificationDispatching)
        {
            self.host = host
            self.authorizationManager = authorizationManager
            self.dispatcher = dispatcher
        }

        func configure()
        {
            assertionFailure("Must not be called")
        }

        func registerHandler(forType _: RemoteNotificationType, handler _: @escaping RemoteNotificationHandler)
        {
            assertionFailure("Must not be called")
        }

        func removeHandler(forType _: RemoteNotificationType)
        {
            assertionFailure("Must not be called")
        }

        func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void)
        {
            let alert = UIAlertController(
                title: "“Sonar” Would Like to Send You Notifications",
                message: "[FAKE] This alert only simulates the system alert.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .default, handler: { _ in
                self.authorizationManager.notificationsStatus = .denied
                completion(.failure(MockError()))
            }))
            alert.addAction(UIAlertAction(title: "Allow", style: .default, handler: { _ in
                self.authorizationManager.notificationsStatus = .allowed
                completion(.success(true))
            }))
            host?.present(alert, animated: false, completion: nil)
        }

        func handleNotification(userInfo _: [AnyHashable: Any], completionHandler _: @escaping RemoteNotificationCompletionHandler)
        {
            assertionFailure("Must not be called")
        }
    }

    private struct MockError: Error {}

    private class NoOpBluetoothNursery: BluetoothNursery
    {
        var hasStarted = false
        func startBluetooth(registration _: Registration?)
        {
            hasStarted = true
        }

        var stateObserver: BluetoothStateObserving = BluetoothStateObserver(initialState: .poweredOn)
        var contactEventRepository: ContactEventRepository = NoOpContactEventRepository()
        var contactEventPersister: ContactEventPersister = NoOpContactEventPersister()
        var broadcaster: BTLEBroadcaster? = NoOpBroadcaster()
    }

    private class NoOpContactEventRepository: ContactEventRepository
    {
        var contactEvents: [ContactEvent] = []

        var delegate: ContactEventRepositoryDelegate?

        func btleListener(_: BTLEListener, didFind _: IncomingBroadcastPayload, for _: BTLEPeripheral)
        {}

        func btleListener(_: BTLEListener, didReadRSSI _: Int, for _: BTLEPeripheral)
        {}

        func btleListener(_: BTLEListener, didReadTxPower _: Int, for _: BTLEPeripheral)
        {}

        func reset()
        {}

        func removeExpiredContactEvents(ttl _: Double)
        {}

        func remove(through _: Date)
        {}
    }

    private class NoOpContactEventPersister: ContactEventPersister
    {
        var items: [UUID: ContactEvent] = [:]

        func update(item _: ContactEvent, key _: UUID)
        {}

        func replaceAll(with _: [UUID: ContactEvent])
        {}

        func reset()
        {}
    }

    private class NoOpBroadcaster: BTLEBroadcaster
    {
        func updateIdentity()
        {}

        func sendKeepalive(value _: Data)
        {}

        func isHealthy() -> Bool
        {
            return false
        }
    }

#endif
