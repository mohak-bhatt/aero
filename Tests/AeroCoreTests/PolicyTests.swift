import Foundation
import XCTest
@testable import AeroCore

final class PolicyTests: XCTestCase {
    private func host(_ page: String = "https://example.com/login", frame: String? = nil,
                      main: Bool = true, scheme: String = "https", origin: String = "example.com",
                      port: Int = 443) -> String? {
        PasswordOriginPolicy.trustedHost(pageURL: URL(string: page),
            frameURL: URL(string: frame ?? page), isMainFrame: main,
            originScheme: scheme, originHost: origin, originPort: port)
    }

    func testStandardHTTPSMainFrameAccepted() {
        XCTAssertEqual(host(), "example.com")
        XCTAssertEqual(host(port: 0), "example.com")
    }
    func testUntrustedOriginsRejected() {
        XCTAssertNil(host(main: false))
        XCTAssertNil(host("http://example.com/login"))
        XCTAssertNil(host(scheme: "http"))
        XCTAssertNil(host(origin: "attacker.com"))
        XCTAssertNil(host(frame: "https://attacker.com/login"))
        XCTAssertNil(host("https://example.com:8443/login", port: 8443))
        XCTAssertNil(host(port: 8443))
        XCTAssertNil(host("file:///tmp/login.html"))
        XCTAssertNil(host(frame: "about:blank"))
        XCTAssertNil(host(frame: "https://example.com/old-document"))
    }
    func testCredentialMatchingNeverExpandsToSubdomains() {
        XCTAssertTrue(PasswordOriginPolicy.matchesCredential(requestHost: "EXAMPLE.COM", credentialHost: "example.com"))
        for host in ["evil.example.com", "example.com.evil.net", "notexample.com", ""] {
            XCTAssertFalse(PasswordOriginPolicy.matchesCredential(requestHost: host, credentialHost: "example.com"))
        }
    }
    func testReleaseLinksStayInConfiguredRepository() {
        XCTAssertTrue(UpdatePolicy.isTrustedReleasePage(URL(string: "https://github.com/mohak-bhatt/aero/releases/tag/v0.1.3")!))
        for link in [
            "http://github.com/mohak-bhatt/aero/releases/tag/v1",
            "https://github.com.evil.net/mohak-bhatt/aero/releases/tag/v1",
            "https://github.com/attacker/aero/releases/tag/v1",
            "https://user@github.com/mohak-bhatt/aero/releases/tag/v1",
            "https://github.com:8443/mohak-bhatt/aero/releases/tag/v1",
            "https://github.com/mohak-bhatt/aero/releases/tag/v1/extra"
        ] {
            XCTAssertFalse(UpdatePolicy.isTrustedReleasePage(URL(string: link)!), link)
        }
    }
}
