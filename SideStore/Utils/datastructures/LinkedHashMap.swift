//
//  LinkedHashMap.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
public final class LinkedHashMap<Key: Hashable, Value>: Sequence {
    fileprivate final class Node {
        let key: Key
        var value: Value
        var next: Node?
        weak var prev: Node?  
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    private var dict: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    public init() { }
    public init(_ dictionary: [Key: Value]) {
        for (key, value) in dictionary {
            _ = self.put(key: key, value: value)
        }
    }
    public var count: Int {
        return dict.count
    }
    public var isEmpty: Bool {
        return dict.isEmpty
    }
    public func get(key: Key) -> Value? {
        return dict[key]?.value
    }
    @discardableResult
    public func put(key: Key, value: Value) -> Value? {
        if let node = dict[key] {
            let oldValue = node.value
            node.value = value
            return oldValue
        } else {
            let newNode = Node(key: key, value: value)
            dict[key] = newNode
            appendNode(newNode)
            return nil
        }
    }
    @discardableResult
    public func remove(key: Key) -> Value? {
        guard let node = dict.removeValue(forKey: key) else { return nil }
        removeNode(node)
        return node.value
    }
    public func clear() {
        dict.removeAll()
        head = nil
        tail = nil
    }
    public func containsKey(_ key: Key) -> Bool {
        return dict[key] != nil
    }
    public func containsValue(_ value: Value) -> Bool where Value: Equatable {
        var current = head
        while let node = current {
            if node.value == value {
                return true
            }
            current = node.next
        }
        return false
    }
    public var keys: [Key] {
        var result = [Key]()
        var current = head
        while let node = current {
            result.append(node.key)
            current = node.next
        }
        return result
    }
    public var values: [Value] {
        var result = [Value]()
        var current = head
        while let node = current {
            result.append(node.value)
            current = node.next
        }
        return result
    }
    public subscript(key: Key) -> Value? {
        get {
            return get(key: key)
        }
        set {
            if let newValue = newValue {
                _ = put(key: key, value: newValue)
            } else {
                _ = remove(key: key)
            }
        }
    }
    public struct Iterator: IteratorProtocol {
        private var current: Node?
        fileprivate init(start: Node?) {
            self.current = start
        }
        public mutating func next() -> (key: Key, value: Value)? {
            guard let node = current else { return nil }
            current = node.next
            return (node.key, node.value)
        }
    }
    public func makeIterator() -> Iterator {
        return Iterator(start: head)
    }
    private func appendNode(_ node: Node) {
        if let tailNode = tail {
            tailNode.next = node
            node.prev = tailNode
            tail = node
        } else {
            head = node
            tail = node
        }
    }
    private func removeNode(_ node: Node) {
        let prevNode = node.prev
        let nextNode = node.next
        if let prevNode = prevNode {
            prevNode.next = nextNode
        } else {
            head = nextNode
        }
        if let nextNode = nextNode {
            nextNode.prev = prevNode
        } else {
            tail = prevNode
        }
        node.prev = nil
        node.next = nil
    }
    public func removeValue(forKey key: Key) -> Value? {
        return remove(key: key)
    }
}

extension LinkedHashMap {
    public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get {
            if let value = self[key] {
                return value
            } else {
                return defaultValue()
            }
        }
        set {
            self[key] = newValue
        }
    }
}
