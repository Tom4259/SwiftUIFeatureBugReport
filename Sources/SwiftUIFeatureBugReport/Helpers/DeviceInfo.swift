//
//  DeviceInfo.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation

public struct DeviceInfo {

    private static let deviceIdentifierKey = "com.swiftuifeaturebugreport.device.identifier"
    
    /// Generate a formatted device information report for bug reports
    public static func generateReport() -> String {

        let app = Bundle.main

        let deviceModel = getDeviceModel()
        let osVersion = getOSVersion()
        let platformName = getPlatformName()
        let appVersion = app.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = app.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return """
        Device: \(deviceModel)
        \(platformName) Version: \(osVersion)
        App Version: \(appVersion) (\(buildNumber))
        """
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

    @available(*, deprecated, message: "Use getOSVersion()")
    public static func getIOSVersion() -> String {

        getOSVersion()
    }

    public static func getDeviceID() -> String {

        let defaults = UserDefaults.standard

        if let existingID = defaults.string(forKey: deviceIdentifierKey) {
            return existingID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: deviceIdentifierKey)

        return newID
    }

    private static func getPlatformName() -> String {
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
