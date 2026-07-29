//
//  LocalProcessSendTests.swift
//
//  Verifies that LocalProcess.send() delivers bytes to the child through
//  the persistent DispatchIO write channel, and that sends after the
//  process stops are dropped safely.
//
#if os(macOS)
import XCTest
@testable import SwiftTerm

final class LocalProcessSendTests: XCTestCase {
    final class Delegate: LocalProcessDelegate {
        let received = XCTestExpectation(description: "echo received")
        var bytes = Data()
        var writeErrors: [Int32] = []
        let marker: Data

        init(marker: String) {
            self.marker = marker.data(using: .utf8)!
        }

        func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}

        func dataReceived(slice: ArraySlice<UInt8>) {
            bytes.append(contentsOf: slice)
            if bytes.range(of: marker) != nil {
                received.fulfill()
            }
        }

        func getWindowSize() -> winsize {
            winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        }

        func writeFailed(_ source: LocalProcess, errno: Int32) {
            writeErrors.append(errno)
        }
    }

    func testSendRoundTripsThroughPty() {
        let marker = "swiftterm-send-\(UInt32.random(in: 0..<UInt32.max))"
        let delegate = Delegate(marker: marker)
        let queue = DispatchQueue(label: "test")
        let process = LocalProcess(delegate: delegate, dispatchQueue: queue)
        process.startProcess(executable: "/bin/cat", args: [], environment: ["TERM=xterm"])
        XCTAssertTrue(process.running)

        let payload = Array("\(marker)\n".utf8)
        process.send(data: payload[...])

        wait(for: [delegate.received], timeout: 5.0)
        // Drain the delegate queue so writeErrors reads are ordered after
        // any pending writeFailed deliveries.
        queue.sync {}
        XCTAssertTrue(delegate.writeErrors.isEmpty)
        process.terminate()
    }

    func testSendAfterTerminateIsDropped() {
        let delegate = Delegate(marker: "unused")
        let process = LocalProcess(delegate: delegate, dispatchQueue: DispatchQueue(label: "test"))
        process.startProcess(executable: "/bin/cat", args: [], environment: ["TERM=xterm"])
        process.terminate()
        XCTAssertFalse(process.running)

        // Must not crash, and must not even enter the write path once
        // stopped — sendCount is only incremented past the guard.
        let countBefore = process.sendCount
        let payload = Array("dropped\n".utf8)
        process.send(data: payload[...])
        XCTAssertEqual(process.sendCount, countBefore)
    }
}
#endif
