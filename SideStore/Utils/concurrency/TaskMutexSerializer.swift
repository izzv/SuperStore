//
//  TaskMutexSerializer.swift
//  SideStore
//
//  Created by Magesh K on 7/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation

actor TaskMutexSerializer {
    static let shared = TaskMutexSerializer()
    private var isLocked = false
    private var suspensionQueue: [CheckedContinuation<Void, Never>] = []
    func lock() async {
        if isLocked {
            await withCheckedContinuation { continuation in
                suspensionQueue.append(continuation)
            }
        } else {
            isLocked = true
        }
    }
    func unlock() {
        if !suspensionQueue.isEmpty {
            let next = suspensionQueue.removeFirst()
            next.resume()
        } else {
            isLocked = false
        }
    }
}
