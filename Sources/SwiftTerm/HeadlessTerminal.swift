//
//  HeadlessTerminal.swift
//  
//
//  Created by Miguel de Icaza on 4/5/20.
//
#if !os(iOS) && !os(Windows)
import Foundation

///
/// A `HeadlessTerminal` provides a terminal emulator that runs a local process, but the output does not go
/// anywhere.   You can use this to script applications and screen scrape the output for example, by accessing the
/// `terminal` from this class.
///
public class HeadlessTerminal : TerminalDelegate, LocalProcessDelegate {
    public private(set) var terminal: Terminal!
    public var process: LocalProcess!
    var onEnd: (_ exitCode: Int32?) -> ()
    var dir: String?

    /// Invoked when a write to the child process failed and the unwritten
    /// input was dropped; receives the errno of the failed write.
    public var onWriteFailed: ((Int32) -> ())?

    public init (queue: DispatchQueue? = nil, options: TerminalOptions = TerminalOptions.default, onEnd: @escaping (_ exitCode: Int32?) -> ())
    {
        self.onEnd = onEnd
        terminal = Terminal(delegate: self, options: options)
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    public func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        onEnd (exitCode)
    }

    public func writeFailed(_ source: LocalProcess, errno: Int32) {
        onWriteFailed? (errno)
    }
    
    public func dataReceived(slice: ArraySlice<UInt8>) {
        //print (String (bytes: slice, encoding: .utf8))
        terminal.feed(buffer: slice)
    }
    
    public func send(data: ArraySlice<UInt8>) {
        process.send (data: data)
    }

    public func send(_ text: String) {
        send (data: ([UInt8] (text.utf8))[...])
        
    }

    /// Changes scrollback size for the underlying terminal at runtime.
    /// - Parameter newScrollback: The new scrollback size in lines. Pass `nil` to disable scrollback.
    public func changeScrollback (_ newScrollback: Int?)
    {
        terminal.changeScrollback(newScrollback)
    }

    public func send(source: Terminal, data: ArraySlice<UInt8>) {
        send (data: data)
    }
    

    public func getWindowSize() -> winsize {
        return winsize(ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols), ws_xpixel: UInt16 (16), ws_ypixel: UInt16 (16))
    }
    
    public func mouseModeChanged(source: Terminal) {
    }

    public func hostCurrentDirectoryUpdated(source: Terminal) {
        dir = source.hostCurrentDirectory
    }
    public func colorChanged(source: Terminal, idx: Int) {
    }
    
    public var images: [([UInt8], Int, Int)] = []
    
    public func createImageFromBitmap (source: Terminal, bytes: inout [UInt8], width: Int, height: Int)  {
        images.append((bytes, width, height))
    }
}

#endif
