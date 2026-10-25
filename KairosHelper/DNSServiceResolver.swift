import Foundation
import SystemConfiguration

enum DNSServiceResolver {
    enum ResolutionError: LocalizedError, Equatable {
        case noCurrentLocation
        case servicesUnavailable
        case interfaceNotFound(String)
        case ambiguousInterface(String)

        var errorDescription: String? {
            switch self {
            case .noCurrentLocation:
                return "无法获取当前网络位置"
            case .servicesUnavailable:
                return "无法获取当前网络位置的网络服务"
            case .interfaceNotFound(let name):
                return "当前网络位置未找到已启用的网络接口：\(name)"
            case .ambiguousInterface(let name):
                return "当前网络位置有多个已启用服务匹配此网络接口，无法确定 DNS 目标：\(name)"
            }
        }
    }

    static func service(forBSDName name: String, in preferences: SCPreferences) throws -> SCNetworkService {
        guard let location = SCNetworkSetCopyCurrent(preferences) else {
            throw ResolutionError.noCurrentLocation
        }
        guard let services = SCNetworkSetCopyServices(location) as? [SCNetworkService] else {
            throw ResolutionError.servicesUnavailable
        }
        // Display names and services in other locations cannot identify the active interface.
        let matches = services.filter { service in
            guard SCNetworkServiceGetEnabled(service),
                  let interface = SCNetworkServiceGetInterface(service) else { return false }
            return SCNetworkInterfaceGetBSDName(interface) as String? == name
        }
        guard let service = matches.first else {
            throw ResolutionError.interfaceNotFound(name)
        }
        guard matches.count == 1 else {
            throw ResolutionError.ambiguousInterface(name)
        }
        return service
    }
}
