//
//  TaskChainSerializer.swift
//  SideStore
//
//  Created by Magesh K on 7/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation

actor TaskChainSerializer {
    static let shared = TaskChainSerializer()
    private var previousTask: Task<Void, Never>?
    func serialize<T>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let localPreviousTask = previousTask
        let newTask = Task {
            _ = await localPreviousTask?.result
            try Task.checkCancellation()
            return try await operation()
        }
        previousTask = Task { _ = await newTask.result }

        return try await withTaskCancellationHandler {
            try await newTask.value     
        } onCancel: {
            newTask.cancel()
        }
    }
}
