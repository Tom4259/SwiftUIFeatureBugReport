//
//  DeviceInfo.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//


import UIKit

struct DeviceInfo {
    
    @MainActor static func generateReport() -> String {
        let device = UIDevice.current
        let app = Bundle.main
        
        let deviceModel = getDeviceModel()
        let appVersion = app.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = app.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return """
        Device: \(deviceModel)
        iOS Version: \(device.systemVersion)
        App Version: \(appVersion) (\(buildNumber))
        Device ID: \(device.identifierForVendor?.uuidString ?? "Unknown")
        """
    }
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
