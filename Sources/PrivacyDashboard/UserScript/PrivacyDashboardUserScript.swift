//
//  PrivacyDashboardUserScript.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import WebKit
import TrackerRadarKit
import UserScript

protocol PrivacyDashboardUserScriptDelegate: AnyObject {
    func userScript(_ userScript: PrivacyDashboardUserScript, didChangeProtectionStateTo protectionState: Bool)
    func userScript(_ userScript: PrivacyDashboardUserScript, setHeight height: Int)
    func userScriptDidRequestClosing(_ userScript: PrivacyDashboardUserScript)
    func userScriptDidRequestShowReportBrokenSite(_ userScript: PrivacyDashboardUserScript)
    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestSubmitBrokenSiteReportWithCategory category: String, description: String)
    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenUrlInNewTab: URL)
    func userScript(_ userScript: PrivacyDashboardUserScript, didSetPermission permission: String, to state: PermissionAuthorizationState)
    func userScript(_ userScript: PrivacyDashboardUserScript, setPermission permission: String, paused: Bool)
}

public enum PrivacyDashboardTheme: String, Encodable {
    case light
    case dark
}

final class PrivacyDashboardUserScript: NSObject, StaticUserScript {

    enum MessageNames: String, CaseIterable {
        case privacyDashboardSetProtection
        case privacyDashboardSetSize
        case privacyDashboardClose
        case privacyDashboardShowReportBrokenSite
        case privacyDashboardSubmitBrokenSiteReport
        case privacyDashboardOpenUrlInNewTab
        case privacyDashboardSetPermission
        case privacyDashboardSetPermissionPaused
    }

    static var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    static var forMainFrameOnly: Bool { false }
    static var source: String = ""
    static var script: WKUserScript = PrivacyDashboardUserScript.makeWKUserScript()
    var messageNames: [String] { MessageNames.allCases.map(\.rawValue) }

    weak var delegate: PrivacyDashboardUserScriptDelegate?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageType = MessageNames(rawValue: message.name) else {
            assertionFailure("PrivacyDashboardUserScript: unexpected message name \(message.name)")
            return
        }

        switch messageType {
        case .privacyDashboardSetProtection:
            handleSetProtection(message: message)
        case .privacyDashboardSetSize:
            handleSetSize(message: message)
        case .privacyDashboardClose:
            handleClose()
        case .privacyDashboardShowReportBrokenSite:
            handleShowReportBrokenSite()
        case .privacyDashboardSubmitBrokenSiteReport:
            handleSubmitBrokenSiteReport(message: message)
        case .privacyDashboardOpenUrlInNewTab:
            handleOpenUrlInNewTab(message: message)
        case .privacyDashboardSetPermission:
            handleSetPermission(message: message)
        case .privacyDashboardSetPermissionPaused:
            handleSetPermissionPaused(message: message)
        }
    }
    
    // MARK: - JS message handlers

    private func handleSetProtection(message: WKScriptMessage) {
        guard let isProtected = message.body as? Bool else {
            assertionFailure("privacyDashboardSetProtection: expected Bool")
            return
        }

        delegate?.userScript(self, didChangeProtectionStateTo: isProtected)
    }
    
    private func handleSetSize(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let height = dict["height"] as? Int else {
            assertionFailure("privacyDashboardSetHeight: expected height to be an Int")
            return
        }

        delegate?.userScript(self, setHeight: height)
    }

    private func handleClose() {
        delegate?.userScriptDidRequestClosing(self)
    }
    
    private func handleShowReportBrokenSite() {
        delegate?.userScriptDidRequestShowReportBrokenSite(self)
    }
    
    private func handleSubmitBrokenSiteReport(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let category = dict["category"] as? String,
              let description = dict["description"] as? String else {
            assertionFailure("privacyDashboardSetHeight: expected { category: String, description: String }")
            return
        }

        delegate?.userScript(self, didRequestSubmitBrokenSiteReportWithCategory: category, description: description)
    }
    
    private func handleOpenUrlInNewTab(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let urlString = dict["url"] as? String,
              let url = URL(string: urlString)
        else {
            assertionFailure("handleOpenUrlInNewTab: expected { url: '...' } ")
            return
        }

        delegate?.userScript(self, didRequestOpenUrlInNewTab: url)
    }
    
    private func handleSetPermission(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let permission = dict["permission"] as? String,
              let state = (dict["value"] as? String).flatMap(PermissionAuthorizationState.init(rawValue:))
        else {
            assertionFailure("privacyDashboardSetPermission: expected { permission: PermissionType, value: PermissionAuthorizationState }")
            return
        }

        delegate?.userScript(self, didSetPermission: permission, to: state)
    }

    private func handleSetPermissionPaused(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let permission = dict["permission"] as? String,
              let paused = dict["paused"] as? Bool
        else {
            assertionFailure("handleSetPermissionPaused: expected { permission: PermissionType, paused: Bool }")
            return
        }

        delegate?.userScript(self, setPermission: permission, paused: paused)
    }

    // MARK: - Calls to script's JS API
    
    func setTrackerInfo(_ tabUrl: URL, trackerInfo: TrackerInfo, webView: WKWebView) {
        guard let trackerBlockingDataJson = try? JSONEncoder().encode(trackerInfo).utf8String() else {
            assertionFailure("Can't encode trackerInfoViewModel into JSON")
            return
        }

        guard let safeTabUrl = try? JSONEncoder().encode(tabUrl).utf8String() else {
            assertionFailure("Can't encode tabUrl into JSON")
            return
        }

        evaluate(js: "window.onChangeRequestData(\(safeTabUrl), \(trackerBlockingDataJson))", in: webView)
    }

    func setProtectionStatus(_ protectionStatus: ProtectionStatus, webView: WKWebView) {
        guard let protectionStatusJson = try? JSONEncoder().encode(protectionStatus).utf8String() else {
            assertionFailure("Can't encode mockProtectionStatus into JSON")
            return
        }
        
        evaluate(js: "window.onChangeProtectionStatus(\(protectionStatusJson))", in: webView)
    }

    func setUpgradedHttps(_ upgradedHttps: Bool, webView: WKWebView) {
        evaluate(js: "window.onChangeUpgradedHttps(\(upgradedHttps))", in: webView)
    }

    func setParentEntity(_ parentEntity: Entity?, webView: WKWebView) {
        if parentEntity == nil { return }

        guard let parentEntityJson = try? JSONEncoder().encode(parentEntity).utf8String() else {
            assertionFailure("Can't encode parentEntity into JSON")
            return
        }

        evaluate(js: "window.onChangeParentEntity(\(parentEntityJson))", in: webView)
    }

    func setTheme(_ theme: PrivacyDashboardTheme?, webView: WKWebView) {
        if theme == nil { return }

        guard let themeJson = try? JSONEncoder().encode(theme).utf8String() else {
            assertionFailure("Can't encode themeName into JSON")
            return
        }

        evaluate(js: "window.onChangeTheme(\(themeJson))", in: webView)
    }

    func setServerTrust(_ serverTrustViewModel: ServerTrustViewModel, webView: WKWebView) {
        guard let certificateDataJson = try? JSONEncoder().encode(serverTrustViewModel).utf8String() else {
            assertionFailure("Can't encode serverTrustViewModel into JSON")
            return
        }

        evaluate(js: "window.onChangeCertificateData(\(certificateDataJson))", in: webView)
    }

    func setIsPendingUpdates(_ isPendingUpdates: Bool, webView: WKWebView) {
        evaluate(js: "window.onIsPendingUpdates(\(isPendingUpdates))", in: webView)
    }
    
    func setLocale(_ currentLocale: String, webView: WKWebView) {
        struct LocaleSetting: Encodable {
            var locale: String
        }
        
        guard let localeSettingJson = try? JSONEncoder().encode(LocaleSetting(locale: currentLocale)).utf8String() else {
            assertionFailure("Can't encode consentInfo into JSON")
            return
        }
        evaluate(js: "window.onChangeLocale(\(localeSettingJson))", in: webView)
    }
    
    func setConsentManaged(_ consentManaged: CookieConsentInfo?, webView: WKWebView) {
        guard let consentDataJson = try? JSONEncoder().encode(consentManaged).utf8String() else {
            assertionFailure("Can't encode consentInfo into JSON")
            return
        }
        evaluate(js: "window.onChangeConsentManaged(\(consentDataJson))", in: webView)
    }
    
    func setPermissions(allowedPermissions: [AllowedPermission], webView: WKWebView) {
        guard let allowedPermissionsJson = try? JSONEncoder().encode(allowedPermissions).utf8String() else {
            assertionFailure("PrivacyDashboardUserScript: could not serialize permissions object")
            return
        }
        
        self.evaluate(js: "window.onChangeAllowedPermissions(\(allowedPermissionsJson))", in: webView)
    }

    private func evaluate(js: String, in webView: WKWebView) {
        webView.evaluateJavaScript(js)
    }

}

extension Data {

    func utf8String() -> String? {
        return String(data: self, encoding: .utf8)
    }

}
