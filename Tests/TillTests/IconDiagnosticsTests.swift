import Foundation
import Testing
@testable import Till

@Suite struct IconFailureTests {
    @Test func offlineCodesMapToOffline() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
        for code in codes { #expect(IconFailure.classify(URLError(code)) == .offline) }
    }

    @Test func tlsCodesMapToTLS() {
        let codes: [URLError.Code] = [
            .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot, .appTransportSecurityRequiresSecureConnection,
        ]
        for code in codes { #expect(IconFailure.classify(URLError(code)) == .tls) }
    }

    @Test func timeoutMapsToTimedOut() {
        #expect(IconFailure.classify(URLError(.timedOut)) == .timedOut)
    }

    @Test func otherErrorsStayNetwork() {
        #expect(IconFailure.classify(URLError(.cannotFindHost)) == .network)
        #expect(IconFailure.classify(TestFailure()) == .network)
    }

    @Test func iconErrorsPassThrough() {
        #expect(IconFailure.classify(IconError.badStatus(503)) == .badStatus(503))
    }

    @Test func logLineNamesDomainAndCodeButNeverTheURL() {
        let error = URLError(
            .notConnectedToInternet,
            userInfo: ["NSErrorFailingURLStringKey": "https://api.iconify.design/search?query=secret-query"])
        let line = IconLog.describe(error, operation: "search")
        #expect(line == "search failed: NSURLErrorDomain -1009")
        #expect(!line.contains("secret-query"))
    }

    @Test func diagnosableCasesHaveDistinctHints() {
        let hints = [IconError.offline, .tls, .timedOut, .network, .badStatus(500)].map(\.hint)
        #expect(Set(hints).count == 5)
    }
}

@Suite struct TestHostSignalsTests {
    @Test func anySignalMeansTesting() {
        #expect(TestHostSignals(configurationFile: false, sessionIdentifier: false, xctestClassLoaded: true).isTesting)
        #expect(TestHostSignals(configurationFile: true, sessionIdentifier: false, xctestClassLoaded: false).isTesting)
        #expect(TestHostSignals(configurationFile: false, sessionIdentifier: true, xctestClassLoaded: false).isTesting)
    }

    @Test func noSignalMeansNormalLaunch() {
        #expect(!TestHostSignals(configurationFile: false, sessionIdentifier: false, xctestClassLoaded: false).isTesting)
    }
}
