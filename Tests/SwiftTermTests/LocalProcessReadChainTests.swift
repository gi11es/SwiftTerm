//
//  LocalProcessReadChainTests.swift
//
//  Regression tests for the read chain silently ending after a failed read.
//
//  DispatchIO reports a failed read operation with `done == true` and no data.
//  The old code only re-armed when `done == false`, so a single failed read
//  left the terminal permanently blind: fd valid, process running, writes
//  still succeeding, but no child output ever read again — a frozen view that
//  reported nothing anywhere.
//
#if os(macOS)
import XCTest
@testable import SwiftTerm

final class LocalProcessReadChainTests: XCTestCase {
    private let maxErrors = 8

    // MARK: - Re-arm decision

    func testRearmsWhenReadCompletedWithError() {
        // The regression: done == true must still re-arm.
        XCTAssertTrue(LocalProcess.shouldRearmRead(running: true, childfd: 5,
                                                   consecutiveErrors: 1, maxErrors: maxErrors))
    }

    func testRearmsOnTransientErrorBeforeThreshold() {
        for n in 1...maxErrors {
            XCTAssertTrue(LocalProcess.shouldRearmRead(running: true, childfd: 5,
                                                       consecutiveErrors: n, maxErrors: maxErrors),
                          "should still re-arm after \(n) consecutive failures")
        }
    }

    func testStopsAfterRepeatedFailuresToAvoidSpinning() {
        XCTAssertFalse(LocalProcess.shouldRearmRead(running: true, childfd: 5,
                                                    consecutiveErrors: maxErrors + 1,
                                                    maxErrors: maxErrors))
    }

    func testDoesNotRearmWhenProcessStopped() {
        XCTAssertFalse(LocalProcess.shouldRearmRead(running: false, childfd: 5,
                                                    consecutiveErrors: 1, maxErrors: maxErrors))
    }

    func testDoesNotRearmWhenDescriptorClosed() {
        XCTAssertFalse(LocalProcess.shouldRearmRead(running: true, childfd: -1,
                                                    consecutiveErrors: 1, maxErrors: maxErrors))
    }

    // MARK: - End-to-end: output still flows after a failed read

    final class Delegate: LocalProcessDelegate {
        var bytes = Data()
        let lock = NSLock()
        var readFailures: [Int32] = []
        let got = XCTestExpectation(description: "child output received after failed read")
        let marker: Data

        init(marker: String) { self.marker = marker.data(using: .utf8)! }

        func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}

        func dataReceived(slice: ArraySlice<UInt8>) {
            lock.lock(); defer { lock.unlock() }
            bytes.append(contentsOf: slice)
            if bytes.range(of: marker) != nil { got.fulfill() }
        }

        func getWindowSize() -> winsize {
            winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        }

        func readFailed(_ source: LocalProcess, errno: Int32) {
            lock.lock(); defer { lock.unlock() }
            readFailures.append(errno)
        }
    }

    /// A failed read must not end the chain: the child's later output still arrives.
    func testOutputStillArrivesAfterSimulatedReadFailure() {
        let marker = "readchain-\(UInt32.random(in: 0..<UInt32.max))"
        let delegate = Delegate(marker: marker)
        let queue = DispatchQueue(label: "readchain-test")
        let process = LocalProcess(delegate: delegate, dispatchQueue: queue)
        process.startProcess(executable: "/bin/cat", args: [], environment: ["TERM=xterm"])
        XCTAssertTrue(process.running)

        // Simulate DispatchIO delivering a completed-but-failed read.
        process.childProcessRead(done: true, data: nil, errno: EINTR)

        // The chain must still be alive: cat echoes what we send.
        let payload = Array("\(marker)\n".utf8)
        process.send(data: payload[...])

        wait(for: [delegate.got], timeout: 5.0)
        queue.sync {}
        XCTAssertTrue(delegate.readFailures.isEmpty,
                      "a single transient failure should not be reported as an abandoned chain")
        process.terminate()
    }

    /// Exhausting the retry budget reports readFailed rather than failing silently.
    func testAbandonedChainIsReported() {
        let delegate = Delegate(marker: "unused")
        let queue = DispatchQueue(label: "readchain-report")
        let process = LocalProcess(delegate: delegate, dispatchQueue: queue)
        process.startProcess(executable: "/bin/cat", args: [], environment: ["TERM=xterm"])

        for _ in 0...(process.maxConsecutiveReadErrors + 1) {
            process.childProcessRead(done: true, data: nil, errno: EIO)
        }
        queue.sync {}

        XCTAssertFalse(delegate.readFailures.isEmpty,
                       "giving up on the read chain must be surfaced to the delegate")
        XCTAssertEqual(delegate.readFailures.first, EIO)
        process.terminate()
    }
}
#endif
