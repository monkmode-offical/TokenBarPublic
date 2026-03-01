import Foundation
import Testing
@testable import TokenBar

@Suite
struct InstallOriginTests {
    @Test
    func detectsHomebrewCaskroom() {
        #expect(
            InstallOrigin
                .isHomebrewCask(
                    appBundleURL: URL(fileURLWithPath: "/opt/homebrew/Caskroom/tokenbar/1.0.0/TokenBar.app")))
        #expect(
            InstallOrigin
                .isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/usr/local/Caskroom/tokenbar/1.0.0/TokenBar.app")))
        #expect(!InstallOrigin.isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/Applications/TokenBar.app")))
    }
}
