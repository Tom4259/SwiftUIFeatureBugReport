//
//  DeviceInfo.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import UIKit

public struct DeviceInfo {
    
    /// Generate a formatted device information report for bug reports
    @MainActor public static func generateReport() -> String {
        
        let device = UIDevice.current
        let app = Bundle.main
        
        let deviceModel = getDeviceModel()
        let appVersion = app.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = app.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return """
        Device: \(deviceModel)
        iOS Version: \(device.systemVersion)
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
    
    @MainActor public static func getIOSVersion() -> String {
        
        UIDevice.current.systemVersion
    }
    
    @MainActor public static func getDeviceID() -> String {
        
        UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
}
