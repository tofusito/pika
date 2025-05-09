import Foundation
import Network

/// Singleton que observa el estado de la red en toda la app
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")

    /// Último estado conocido de la red
    private(set) var isConnected: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = (path.status == .satisfied)
            debugPrint("🔌 Network status changed:", path.status)
        }
        monitor.start(queue: queue)
    }
} 