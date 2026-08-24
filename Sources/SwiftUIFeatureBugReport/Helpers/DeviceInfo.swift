//
//  DeviceInfo.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation

public struct DeviceInfo {

    /// The structured environment attached to every request.
    ///
    /// Replaces v1's `generateReport()` formatted blob - that shape only existed because a GitHub
    /// issue has a single text field.
    public static func current() -> DeviceEnvironment {

        DeviceEnvironment(appVersion: getAppVersion(),
                          buildNumber: getBuildNumber(),
                          osVersion: getOSVersion(),
                          deviceModel: getDeviceModel(),
                          platform: getPlatformName())
    }

    /// Get individual device information components
    public static func getDeviceModel() -> String {
        
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        
        let identifier = machineMirror.children.reduce("") { identifier, element in
            
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        return identifier
    }
    
    public static func getAppVersion() -> String {
        
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    public static func getBuildNumber() -> String {
        
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    public static func getOSVersion() -> String {

        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    public static func getPlatformName() -> String {
        #if targetEnvironment(macCatalyst)
        "macCatalyst"
        #elseif os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(visionOS)
        "visionOS"
        #elseif os(Linux)
        "Linux"
        #elseif os(Windows)
        "Windows"
        #else
        "OS"
        #endif
    }
}
