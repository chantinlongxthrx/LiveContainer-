//
//  EntitlementManager.swift
//  LiveContainerSwiftUI
//
//  Manages app entitlements for sideloaded apps
//

import Foundation
import Security

class EntitlementManager {
    static let shared = EntitlementManager()
    
    /// Adds extended virtual addressing entitlement to an app's entitlements plist
    func addExtendedVirtualAddressing(to appPath: String) throws {
        try addEntitlement(key: "com.apple.developer.kernel.extended-virtual-addressing", value: true, to: appPath)
    }
    
    /// Adds increased memory limit entitlement to an app's entitlements plist
    func addIncreasedMemoryLimit(to appPath: String) throws {
        try addEntitlement(key: "com.apple.developer.kernel.increased-memory-limit", value: true, to: appPath)
    }
    
    /// Generic method to add an entitlement to an app's entitlements plist
    private func addEntitlement(key: String, value: Any, to appPath: String) throws {
        let entitlementsPath = URL(fileURLWithPath: appPath).appendingPathComponent("Entitlements.plist").path
        let fileManager = FileManager.default
        
        // Read existing entitlements
        var entitlements: [String: Any]
        
        if fileManager.fileExists(atPath: entitlementsPath) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: entitlementsPath)) else {
                throw NSError(domain: "EntitlementManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read entitlements file"])
            }
            
            guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw NSError(domain: "EntitlementManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid entitlements plist format"])
            }
            
            entitlements = dict
        } else {
            // Create new entitlements dictionary if it doesn't exist
            entitlements = [:]
        }
        
        // Add the entitlement
        entitlements[key] = value
        
        // Serialize and write back
        let data = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: entitlementsPath))
    }
    
    /// Checks if extended virtual addressing is already enabled
    func hasExtendedVirtualAddressing(in appPath: String) -> Bool {
        return hasEntitlement(key: "com.apple.developer.kernel.extended-virtual-addressing", in: appPath)
    }
    
    /// Checks if increased memory limit is already enabled
    func hasIncreasedMemoryLimit(in appPath: String) -> Bool {
        return hasEntitlement(key: "com.apple.developer.kernel.increased-memory-limit", in: appPath)
    }
    
    /// Generic method to check if an entitlement exists
    private func hasEntitlement(key: String, in appPath: String) -> Bool {
        let entitlementsPath = URL(fileURLWithPath: appPath).appendingPathComponent("Entitlements.plist").path
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: entitlementsPath) else { return false }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: entitlementsPath)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        
        if let value = dict[key] as? Bool {
            return value
        }
        
        return false
    }
}
