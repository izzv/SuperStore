//
//  ConsoleCapture.swift
//  SideStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
import Foundation

protocol ConsoleLogger{
    func startCapturing()
    func stopCapturing()
}

public class AbstractConsoleLogger<T: OutputStream>: ConsoleLogger{
    var outPipe: Pipe?
    var errPipe: Pipe?
    var outputHandle: FileHandle?
    var errorHandle:  FileHandle?
    var originalStdout: Int32?
    var originalStderr: Int32?
    let ostream: T
    let writeQueue = DispatchQueue(label: "async-write-queue")
    public init(stream: T) throws {
        if Self.self === AbstractConsoleLogger.self {
            throw AbstractClassError.abstractInitializerInvoked
        }
        self.ostream = stream
    }
    deinit {
        stopCapturing()
    }
    public func startCapturing() {                          

        guard outPipe == nil, errPipe == nil else {
            return
        }
        self.outPipe = Pipe()
        self.errPipe = Pipe()
        outputHandle = self.outPipe?.fileHandleForReading
        errorHandle = self.errPipe?.fileHandleForReading

        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        let redirectedOutStream = self.outPipe?.fileHandleForWriting.fileDescriptor ?? -1
        let redirectedErrStream = self.errPipe?.fileHandleForWriting.fileDescriptor ?? -1
        dup2(redirectedOutStream, STDOUT_FILENO)
        dup2(redirectedErrStream, STDERR_FILENO)

        setvbuf(stdout, nil, _IONBF, 0)  
        setvbuf(stderr, nil, _IONBF, 0)  
        setupReadabilityHandler(for: outputHandle, isError: false)
        setupReadabilityHandler(for: errorHandle, isError: true)
    }

    let shutdownLock = NSLock()

    private func setupReadabilityHandler(for handle: FileHandle?, isError: Bool) {
        handle?.readabilityHandler = readHandler(isError: isError)
    }

    private func readHandler(isError: Bool) -> (FileHandle) -> Void {
        return { [weak self] _ in
            self?.shutdownLock.lock()
            defer { self?.shutdownLock.unlock() }

            guard let self = self else { return }
            let handle = isError ? self.errorHandle : self.outputHandle
            guard let data = handle?.availableData else { return }

            writeQueue.async {
                try? self.writeData(data)
            }

            guard let fd = isError ? self.originalStderr : self.originalStdout else {
                return
            }

            guard fcntl(fd, F_GETFD) != -1 else {
                return
            }

            data.withUnsafeBytes { rawBufferPointer in
                guard let base = rawBufferPointer.baseAddress else { return }
                var remaining = data.count
                var offset = 0
                let maxChunkSize = 16 * 1024 

                while remaining > 0 {
                    let chunkSize = min(maxChunkSize, remaining)
                    let written = write(fd, base.advanced(by: offset), chunkSize)

                    if written < 0 {
                        break
                    }

                    remaining -= written
                    offset += written
                }
            }
        }
    }

    func writeData(_ data: Data) throws {
        throw AbstractClassError.abstractMethodInvoked
    }

    func stopCapturing() {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }

        ostream.close()
        if let stdout = originalStdout, stdout != STDOUT_FILENO {
            dup2(stdout, STDOUT_FILENO)
            close(stdout)
        }
        if let stderr = originalStderr, stderr != STDERR_FILENO {
            dup2(stderr, STDERR_FILENO)
            close(stderr)
        }
        outPipe?.fileHandleForReading.readabilityHandler = nil
        errPipe?.fileHandleForReading.readabilityHandler = nil
        outPipe = nil
        errPipe = nil
        outputHandle = nil
        errorHandle = nil
        originalStdout = nil
        originalStderr = nil
    }
}

public class UnBufferedConsoleLogger<T: OutputStream>: AbstractConsoleLogger<T> {

    required override init(stream: T) {
        try! super.init(stream: stream)
    }
    override func writeData(_ data: Data) throws {
        ostream.write(data)
    }
}

public class BufferedConsoleLogger<T: OutputStream>: AbstractConsoleLogger<T> {

    private let maxBufferSize: Int
    private var bufferedData = Data()
    required init(stream: T, bufferSize: Int = 1024) {
        self.maxBufferSize = bufferSize
        try! super.init(stream: stream)
    }
    override func writeData(_ data: Data) throws {
        self.bufferedData.append(data)
        if self.bufferedData.count >= self.maxBufferSize {
            self.flushBuffer()
        }
    }
    private func flushBuffer() {
        ostream.write(bufferedData)
        bufferedData.removeAll()
    }

    override func stopCapturing() {
        flushBuffer()
        super.stopCapturing()
    }
}
