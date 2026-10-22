import Darwin
import Foundation
import SystemConfiguration

/// Reads only the system's current IPv4 gateway, never a client-supplied address.
struct GatewayInfoReader {
    private struct Gateway: Equatable {
        let ip: String
        let interfaceIndex: UInt32
    }

    func read() throws -> (ip: String?, mac: String?) {
        guard let gateway = try currentGateway() else { return (nil, nil) }
        let data = try readARPTable()
        let mac = try Self.macAddress(in: data, ip: gateway.ip, interfaceIndex: gateway.interfaceIndex)
        // Do not combine a gateway from one network with a MAC from another.
        guard try currentGateway() == gateway else { throw ReadError.networkChanged }
        return (gateway.ip, mac)
    }

    private func currentGateway() throws -> Gateway? {
        guard let store = SCDynamicStoreCreate(nil, "KairosHelper" as CFString, nil, nil) else {
            throw ReadError.configurationUnavailable
        }
        guard let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) else {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw ReadError.configurationUnavailable
        }
        guard let ip = dictionary["Router"] as? String else { return nil }
        var address = in_addr()
        guard inet_pton(AF_INET, ip, &address) == 1,
              let interface = dictionary["PrimaryInterface"] as? String else {
            throw ReadError.configurationUnavailable
        }
        let index = if_nametoindex(interface)
        guard index != 0 else { throw ReadError.configurationUnavailable }
        return Gateway(ip: ip, interfaceIndex: index)
    }

    private func readARPTable() throws -> Data {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        // The table can grow between the size query and the actual read.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
                throw ReadError.systemCall(errno)
            }
            guard size > 0 else { return Data() }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { bytes in
                sysctl(&mib, UInt32(mib.count), bytes.baseAddress, &size, nil, 0)
            }
            if result == 0 {
                data.count = size
                return data
            }
            let code = errno
            guard code == ENOMEM else { throw ReadError.systemCall(code) }
        }
        throw ReadError.systemCall(ENOMEM)
    }

    static func macAddress(in data: Data, ip: String, interfaceIndex: UInt32) throws -> String? {
        var target = in_addr()
        guard inet_pton(AF_INET, ip, &target) == 1 else { throw ReadError.configurationUnavailable }
        return try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard bytes.count - offset >= MemoryLayout<rt_msghdr>.size else {
                    throw ReadError.malformedTable
                }
                let header = bytes.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let length = Int(header.rtm_msglen)
                guard length >= MemoryLayout<rt_msghdr>.size, length <= bytes.count - offset,
                      header.rtm_version == RTM_VERSION else {
                    throw ReadError.malformedTable
                }
                defer { offset += length }
                guard UInt32(header.rtm_index) == interfaceIndex else { continue }

                var cursor = offset + MemoryLayout<rt_msghdr>.size
                let end = offset + length
                var matchesIP = false
                var mac: String?
                for index in 0..<Int(RTAX_MAX) where (header.rtm_addrs & (1 << index)) != 0 {
                    guard end - cursor >= 2 else { throw ReadError.malformedTable }
                    let size = Int(bytes[cursor])
                    let family = Int32(bytes[cursor + 1])
                    // Darwin routing messages align sockaddr records to 32 bits, even on arm64.
                    let stride = size == 0 ? 4 : (size + 3) & ~3
                    guard stride <= end - cursor else { throw ReadError.malformedTable }
                    if index == Int(RTAX_DST), family == AF_INET {
                        guard size >= MemoryLayout<sockaddr_in>.size else { throw ReadError.malformedTable }
                        let address = bytes.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self)
                        matchesIP = address.sin_addr.s_addr == target.s_addr
                    } else if index == Int(RTAX_GATEWAY), family == AF_LINK {
                        guard size >= 8 else { throw ReadError.malformedTable }
                        let nameLength = Int(bytes[cursor + 5])
                        let macLength = Int(bytes[cursor + 6])
                        guard 8 + nameLength + macLength <= size else { throw ReadError.malformedTable }
                        if macLength == 6 {
                            let start = cursor + 8 + nameLength
                            let address = Array(bytes[start..<(start + macLength)])
                            // A redacted address must never participate in scene matching.
                            if address != [2, 0, 0, 0, 0, 0], address != [0, 0, 0, 0, 0, 0] {
                                mac = address.map { String(format: "%02X", $0) }.joined(separator: ":")
                            }
                        }
                    }
                    cursor += stride
                }
                if matchesIP, let mac { return mac }
            }
            return nil
        }
    }

    private enum ReadError: LocalizedError {
        case configurationUnavailable
        case networkChanged
        case systemCall(Int32)
        case malformedTable

        var errorDescription: String? {
            switch self {
            case .configurationUnavailable: return "无法读取当前 IPv4 网关及接口"
            case .networkChanged: return "读取网关期间网络发生变化"
            case .systemCall(let code): return "读取 ARP 表失败：\(String(cString: strerror(code))) (\(code))"
            case .malformedTable: return "系统返回的 ARP 表格式无效"
            }
        }
    }
}
