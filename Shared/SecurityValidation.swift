// Security helpers for XPC client validation and path hardening

import Foundation
import Security

enum XPCSecurity {
    /// Must match SMAuthorizedClients in WireGuardMultiTunnelHelper/Info.plist
    static let authorizedAppRequirement =
        "anchor apple generic and identifier \"WireGuardMultiTunnel\" and certificate leaf[subject.OU] = \"4JD8RUCQ2W\""

    /// Must match SMPrivilegedExecutables in WireGuardMultiTunnel/Info.plist
    static let authorizedHelperRequirement =
        "anchor apple generic and identifier \"WireGuardMultiTunnelHelper\" " +
        "and certificate leaf[subject.OU] = \"4JD8RUCQ2W\""

    static func applyListenerClientRequirement(to listener: NSXPCListener) {
        if #available(macOS 13.0, *) {
            listener.setConnectionCodeSigningRequirement(authorizedAppRequirement)
        }
    }

    static func applyHelperRequirement(to connection: NSXPCConnection) {
        if #available(macOS 13.0, *) {
            connection.setCodeSigningRequirement(authorizedHelperRequirement)
        }
    }

    static func isAuthorizedAppConnection(_ connection: NSXPCConnection) -> Bool {
        validatePeerProcess(connection, requirement: authorizedAppRequirement)
    }

    static func isAuthorizedHelperConnection(_ connection: NSXPCConnection) -> Bool {
        validatePeerProcess(connection, requirement: authorizedHelperRequirement)
    }

    private static func validatePeerProcess(_ connection: NSXPCConnection,
                                            requirement: String) -> Bool
    {
        if #available(macOS 13.0, *) {
            // macOS 13+ enforces requirements via setCodeSigningRequirement APIs.
            return true
        }

        let peerProcessIdentifier = connection.processIdentifier
        guard peerProcessIdentifier > 0 else {
            NSLog("XPCSecurity: invalid peer process identifier")
            return false
        }

        var code: SecCode?
        let attributes = [kSecGuestAttributePid: peerProcessIdentifier] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard copyStatus == errSecSuccess, let guestCode = code else {
            NSLog("XPCSecurity: failed to copy guest code (\(copyStatus))")
            return false
        }

        var secRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
              let secRequirement = secRequirement
        else {
            NSLog("XPCSecurity: failed to create code requirement")
            return false
        }

        let validityStatus = SecCodeCheckValidity(guestCode, [], secRequirement)
        if validityStatus != errSecSuccess {
            NSLog("XPCSecurity: code validity check failed (\(validityStatus))")
            return false
        }

        return true
    }
}

enum PathSecurity {
    static func validateDirectoryPath(_ path: String) -> String? {
        guard isSafeAbsolutePath(path) else { return nil }

        let standardizedPath = (path as NSString).standardizingPath
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        return resolveRealPath(standardizedPath)
    }

    static func validateBinaryPath(_ path: String, expectedBasename: String) -> String? {
        guard isSafeAbsolutePath(path) else { return nil }

        let standardizedPath = (path as NSString).standardizingPath
        guard (standardizedPath as NSString).lastPathComponent == expectedBasename else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }

        return resolveRealPath(standardizedPath)
    }

    static func validateExecutableBinaryPath(_ path: String, expectedBasename: String) -> String? {
        guard let resolvedPath = validateBinaryPath(path, expectedBasename: expectedBasename) else {
            return nil
        }

        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else { return nil }
        return resolvedPath
    }

    private static func isSafeAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("..")
    }

    private static func resolveRealPath(_ path: String) -> String? {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix("/"), !resolvedPath.contains("/../") else { return nil }
        return resolvedPath
    }
}
