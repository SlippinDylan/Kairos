//
//  IPQueryModels.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

struct IPQueryResult {
    let ip: String
    let asn: String
    let organization: String
    let coordinates: Coordinates?
    let location: LocationInfo
    let registrationCountry: String
    let timezone: String
    let ipType: String
}

struct Coordinates {
    let latitude: Double
    let longitude: Double

    var displayString: String {
        let latitudeDMS = GeoUtils.degreesToDMS(decimal: latitude, isLatitude: true)
        let longitudeDMS = GeoUtils.degreesToDMS(decimal: longitude, isLatitude: false)
        return "\(longitudeDMS), \(latitudeDMS)"
    }
}

struct LocationInfo {
    let state: String?
    let city: String?
    let zipCode: String?
    let countryCode: String?
    let countryName: String?
    let continentCode: String?
    let continentName: String?

    var cityDisplay: String {
        let parts = [state, city, zipCode].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    var usageLocation: String {
        var parts: [String] = []
        if let countryCode {
            parts.append("\(GeoUtils.countryFlag(countryCode: countryCode))[\(countryCode)]\(countryName ?? "")")
        } else if let countryName, !countryName.isEmpty {
            parts.append(countryName)
        }
        if let continentCode {
            parts.append("[\(continentCode)]\(continentName ?? "")")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }
}

// Both wire formats are normalized here; these types are not persisted or exported.
struct IPAPIQueryResponse: Decodable {
    let ip: String
    let asn: String?
    let organization: String?
    let usageType: String?
    let registrationCountryCode: String?
    let location: LocationDetail

    private enum CodingKeys: String, CodingKey {
        case ip, docs, asn, company, location, city, region, country, lat, lon, timezone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ip = try values.decode(String.self, forKey: .ip)
        // The provider documents `docs` as the marker of its anonymous response.
        if values.contains(.docs) {
            _ = try values.decode(String.self, forKey: .docs)
            asn = try values.decodeIfPresent(String.self, forKey: .asn)
            organization = try values.decodeIfPresent(String.self, forKey: .company)
            usageType = nil
            registrationCountryCode = nil
            location = LocationDetail(
                city: try values.decodeIfPresent(String.self, forKey: .city),
                state: try values.decodeIfPresent(String.self, forKey: .region),
                country: try values.decodeIfPresent(String.self, forKey: .country),
                countryCode: nil,
                continent: nil,
                latitude: try values.decodeIfPresent(Double.self, forKey: .lat),
                longitude: try values.decodeIfPresent(Double.self, forKey: .lon),
                timezone: try values.decodeIfPresent(String.self, forKey: .timezone),
                zip: nil
            )
        } else {
            let asnInfo = try values.decodeIfPresent(ASNInfo.self, forKey: .asn)
            let company = try values.decodeIfPresent(CompanyInfo.self, forKey: .company)
            asn = asnInfo?.asn.map { "AS\($0)" }
            organization = company?.name
            usageType = company?.type
            registrationCountryCode = asnInfo?.country
            location = try values.decodeIfPresent(LocationDetail.self, forKey: .location) ?? .unavailable
        }
    }

    private struct ASNInfo: Decodable {
        let asn: Int?
        let country: String?
    }

    private struct CompanyInfo: Decodable {
        let name: String?
        let type: String?
    }

    struct LocationDetail: Decodable {
        let city: String?
        let state: String?
        let country: String?
        let countryCode: String?
        let continent: String?
        let latitude: Double?
        let longitude: Double?
        let timezone: String?
        let zip: String?

        // A private or unallocated address can legitimately have no location record.
        static let unavailable = LocationDetail(city: nil, state: nil, country: nil,
            countryCode: nil, continent: nil, latitude: nil, longitude: nil,
            timezone: nil, zip: nil)

        enum CodingKeys: String, CodingKey {
            case city, state, country, continent, latitude, longitude, timezone, zip
            case countryCode = "country_code"
        }
    }
}
