import Darwin
import Foundation

@main
struct GatewayInfoReaderTests {
    static func main() throws {
        let expected = "00:0C:29:6D:18:98"
        let mac: [UInt8] = [0, 12, 41, 109, 24, 152]
        let matching = message(ip: "10.10.0.1", interface: 13, mac: mac)
        try expect(try lookup(matching) == expected, "normal gateway")
        try expect(try lookup(Data()) == nil, "empty table is not a syscall failure")
        try expect(try lookup(message(ip: "10.10.0.2", interface: 13, mac: mac)) == nil, "wrong IP")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 15, mac: mac)) == nil, "wrong interface")

        let otherInterface = message(ip: "10.10.0.1", interface: 15, mac: [1, 2, 3, 4, 5, 6])
        try expect(try lookup(otherInterface + matching) == expected, "same IP on two interfaces")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 13, mac: [])) == nil, "unresolved neighbor")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 13, mac: [2, 0, 0, 0, 0, 0])) == nil, "redacted MAC")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 13, mac: [0, 0, 0, 0, 0, 0])) == nil, "zero MAC")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 13, mac: mac, name: [101])) == expected, "link name offset")
        try expect(try lookup(message(ip: "10.10.0.1", interface: 13, mac: mac, trailingMask: true)) == expected, "Darwin 32-bit sockaddr alignment")

        try expectMalformed(Data(matching.prefix(10)), "truncated header")
        var badLength = matching
        badLength[0] = 0
        badLength[1] = 0
        try expectMalformed(badLength, "zero message length")
        try expectMalformed(Data(matching.dropLast()), "truncated message")
        var badAddress = matching
        badAddress[MemoryLayout<rt_msghdr>.size] = 255
        try expectMalformed(badAddress, "sockaddr exceeds message")
        var badMAC = matching
        badMAC[MemoryLayout<rt_msghdr>.size + MemoryLayout<sockaddr_in>.size + 6] = 255
        try expectMalformed(badMAC, "MAC exceeds sockaddr")
        print("GatewayInfoReader: 15 checks passed")

        if CommandLine.arguments.contains("--read-current") {
            let gateway = try GatewayInfoReader().read()
            print("uid=\(geteuid()) gateway=\(gateway.ip ?? "-") MAC=\(gateway.mac ?? "-")")
        }
    }

    private static func lookup(_ data: Data) throws -> String? {
        try GatewayInfoReader.macAddress(in: data, ip: "10.10.0.1", interfaceIndex: 13)
    }

    private static func expect(_ condition: Bool, _ name: String) throws {
        if !condition { throw Failure(message: name) }
    }

    private static func expectMalformed(_ data: Data, _ name: String) throws {
        do {
            _ = try lookup(data)
        } catch {
            return
        }
        throw Failure(message: "Accepted malformed data: \(name)")
    }

    private static func message(
        ip: String,
        interface: UInt16,
        mac: [UInt8],
        name: [UInt8] = [],
        trailingMask: Bool = false
    ) -> Data {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = UInt8(AF_INET)
        precondition(inet_pton(AF_INET, ip, &destination.sin_addr) == 1)
        var addresses = withUnsafeBytes(of: destination) { Data($0) }
        let linkLength = 8 + name.count + mac.count
        var link = Data([UInt8(linkLength), UInt8(AF_LINK), 0, 0, UInt8(IFT_ETHER), UInt8(name.count), UInt8(mac.count), 0])
        link.append(contentsOf: name + mac)
        link.append(contentsOf: repeatElement(UInt8(0), count: ((linkLength + 3) & ~3) - linkLength))
        addresses.append(link)
        if trailingMask { addresses.append(contentsOf: [0, 0, 0, 0]) }
        var header = rt_msghdr()
        header.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + addresses.count)
        header.rtm_version = UInt8(RTM_VERSION)
        header.rtm_index = interface
        header.rtm_addrs = RTA_DST | RTA_GATEWAY | (trailingMask ? RTA_NETMASK : 0)
        return withUnsafeBytes(of: header) { Data($0) } + addresses
    }

    private struct Failure: Error {
        let message: String
    }
}
