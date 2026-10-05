import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет классификацию транспортных ошибок batch-запросов.
 */
final class NetworkErrorClassifierTests: XCTestCase {

    /**
     Проверяет разрешение retry для временных сетевых ошибок.
     */
    func testTransientNetworkErrorsAreRetryable() {
        let retryableCodes: [URLError.Code] = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet
        ]

        for code in retryableCodes {
            XCTAssertTrue(NetworkErrorClassifier.isRetryable(URLError(code)))
        }
    }

    /**
     Проверяет запрет retry для TLS, certificate и ATS ошибок.
     */
    func testSecurityErrorsAreNotRetryable() {
        let terminalCodes: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired,
            .appTransportSecurityRequiresSecureConnection
        ]

        for code in terminalCodes {
            XCTAssertFalse(NetworkErrorClassifier.isRetryable(URLError(code)))
        }
    }

    /**
     Проверяет запрет retry для неизвестной транспортной ошибки.
     */
    func testUnknownErrorIsNotRetryable() {
        let error = NSError(domain: "test.network.error", code: 1)

        XCTAssertFalse(NetworkErrorClassifier.isRetryable(error))
    }
}
