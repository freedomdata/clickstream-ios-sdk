import UIKit
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет callback появления экранов.
 */
final class ScreenTrackingTests: XCTestCase {

    /**
     Сбрасывает callback появления экрана после каждого теста.
     */
    override func tearDown() {
        ScreenTracking.setOnScreenAppear(nil)
        super.tearDown()
    }

    /**
     Проверяет установку nil callback без падения.
     */
    func test_setOnScreenAppear_nil_doesNotCrash() {
        ScreenTracking.setOnScreenAppear(nil)
    }

    /**
     Проверяет вызов callback при передаче имени экрана.
     */
    func test_setOnScreenAppear_block_reportScreenName_invokesCallback() {
        let expectation = expectation(description: "callback")
        var receivedName: String?
        ScreenTracking.setOnScreenAppear { name in
            receivedName = name
            expectation.fulfill()
        }
        ScreenTracking.reportScreenName("TestViewController")
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedName, "TestViewController")
    }

    /**
     Проверяет отсутствие вызова callback после сброса в nil.
     */
    func test_setOnScreenAppear_nil_afterBlock_reportScreenName_doesNotInvoke() {
        var callCount = 0
        ScreenTracking.setOnScreenAppear { _ in callCount += 1 }
        ScreenTracking.setOnScreenAppear(nil)
        ScreenTracking.reportScreenName("SomeScreen")
        XCTAssertEqual(callCount, 0)
    }

    /**
     Проверяет отправку имени экрана без callback без падения.
     */
    func test_reportScreenName_withNoCallback_doesNotCrash() {
        ScreenTracking.setOnScreenAppear(nil)
        ScreenTracking.reportScreenName("NoCallback")
    }
}