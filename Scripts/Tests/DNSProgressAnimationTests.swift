import Foundation
import SwiftUI

enum L10n {
    static func format(_ key: String, _ arguments: CVarArg...) -> String { key }
}

@main
struct DNSProgressAnimationTests {
    static func main() {
        var checks = 0
        var previous = -1.0
        let count = defaultTestSites.count
        for domain in 0..<count {
            for round in 1...10 {
                let progress = DNSTestProgress(currentDomain: defaultTestSites[domain], currentRound: round, completedDomains: domain, totalDomains: count)
                precondition(progress.overallProgress > previous && progress.overallProgress < 1)
                precondition(abs(progress.overallProgress - Double(domain * 10 + round - 1) / Double(count * 10)) < 0.000001)
                previous = progress.overallProgress
                checks += 1
            }
        }
        let size = CGSize(width: 508, height: 80)
        let track = DNSProgressFlow.track(in: size)
        precondition(track.minX == 0 && track.minY == 0)
        precondition(track.size == size, "The grid must fill the entire sheet")
        checks += 1
        let first = DNSProgressFlow.chromaticPhase(position: 0.25, time: 0.0875)
        let movedRight = DNSProgressFlow.chromaticPhase(position: 0.5, time: 0.175)
        precondition(abs(first - movedRight) < 0.000001 && first > 0.99, "The color peak must move left to right")
        precondition(abs(DNSProgressFlow.chromaticPhase(position: 0.25, time: 1.0875) - first) < 0.000001, "Flow must repeat seamlessly")
        for index in 0...32 {
            let position = Double(index) / 32
            let before = DNSProgressFlow.chromaticPhase(position: position, time: 0.9999)
            let after = DNSProgressFlow.chromaticPhase(position: position, time: 1.0001)
            precondition(abs(before - after) < 0.001, "The loop boundary must stay continuous across the entire fill")
            let color = DNSProgressFlow.components(position: position, time: Double(index) / 7)
            let luminance = color.red * 0.2126 + color.green * 0.7152 + color.blue * 0.0722
            precondition(abs(luminance - 0.24) < 0.000001, "Color flow must not create a moving brightness peak")
            checks += 1
        }
        checks += 1
        print("DNS progress and color flow: \(checks) checks passed")
    }
}
