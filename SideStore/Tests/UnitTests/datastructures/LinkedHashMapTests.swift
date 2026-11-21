//
//  LinkedHashMapTests.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import XCTest

class LeakTester {
    let id: Int
    var onDeinit: (() -> Void)?
    init(id: Int, onDeinit: (() -> Void)? = nil) {
        self.id = id
        self.onDeinit = onDeinit
    }
    deinit {
        onDeinit?()
    }
}

final class LinkedHashMapTests: XCTestCase {
    func testInsertionAndOrder() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "one", value: 1)
        map.put(key: "two", value: 2)
        map.put(key: "three", value: 3)
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map.keys, ["one", "two", "three"], "Insertion order should be preserved")
        var iteratedKeys = [String]()
        for (key, _) in map {
            iteratedKeys.append(key)
        }
        XCTAssertEqual(iteratedKeys, ["one", "two", "three"], "Iterator should follow insertion order")
    }
    func testUpdateDoesNotChangeOrder() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "a", value: 1)
        map.put(key: "b", value: 2)
        map.put(key: "c", value: 3)
        map.put(key: "b", value: 20)
        XCTAssertEqual(map.get(key: "b"), 20)
        XCTAssertEqual(map.keys, ["a", "b", "c"], "Order should not change on update")
    }
    func testRemoval() {
        let map = LinkedHashMap<Int, String>()
        map.put(key: 1, value: "one")
        map.put(key: 2, value: "two")
        map.put(key: 3, value: "three")
        let removed = map.remove(key: 2)
        XCTAssertEqual(removed, "two")
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map.keys, [1, 3])
        let removedNil = map.remove(key: 4)
        XCTAssertNil(removedNil)
    }
    func testClear() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "x", value: 100)
        map.put(key: "y", value: 200)
        XCTAssertEqual(map.count, 2)
        map.clear()
        XCTAssertEqual(map.count, 0)
        XCTAssertTrue(map.isEmpty)
        XCTAssertEqual(map.keys, [])
        XCTAssertEqual(map.values, [])
    }
    func testSubscript() {
        let map = LinkedHashMap<String, Int>()
        map["alpha"] = 10
        XCTAssertEqual(map["alpha"], 10)
        map["alpha"] = 20
        XCTAssertEqual(map["alpha"], 20)
        map["alpha"] = nil
        XCTAssertNil(map["alpha"])
    }
    func testContains() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "key1", value: 1)
        map.put(key: "key2", value: 2)
        XCTAssertTrue(map.containsKey("key1"))
        XCTAssertFalse(map.containsKey("key3"))
        XCTAssertTrue(map.containsValue(1))
        XCTAssertFalse(map.containsValue(99))
    }
    func testInitializationFromDictionary() {
        let dictionary: [String: Int] = ["a": 1, "b": 2, "c": 3]
        let map = LinkedHashMap(dictionary)
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(Set(map.keys), Set(["a", "b", "c"]))
    }
    func testIteration() {
        let map = LinkedHashMap<Int, String>()
        let pairs = [(1, "one"), (2, "two"), (3, "three")]
        for (key, value) in pairs {
            map.put(key: key, value: value)
        }
        var iteratedPairs = [(Int, String)]()
        for (key, value) in map {
            iteratedPairs.append((key, value))
        }
        XCTAssertEqual(iteratedPairs.count, pairs.count, "Iterated count should match inserted count")
        for (iter, expected) in zip(iteratedPairs, pairs) {
            XCTAssertEqual(iter.0, expected.0, "Keys should match in order")
            XCTAssertEqual(iter.1, expected.1, "Values should match in order")
        }
    }
    func testMemoryLeak() {
        weak var weakMap: LinkedHashMap<Int, LeakTester>?
        var deinitCalled = false
        do {
            let map = LinkedHashMap<Int, LeakTester>()
            let tester = LeakTester(id: 1) { deinitCalled = true }
            map.put(key: 1, value: tester)
            weakMap = map
            XCTAssertNotNil(map.get(key: 1))
        }
        XCTAssertNil(weakMap, "LinkedHashMap should be deallocated when out of scope")
        XCTAssertTrue(deinitCalled, "LeakTester should be deallocated, indicating no memory leak")
    }
    func testMemoryLeakOnRemoval() {
        var deinitCalledForTester1 = false
        var deinitCalledForTester2 = false
        let map = LinkedHashMap<Int, LeakTester>()
        autoreleasepool {
            let tester1 = LeakTester(id: 1) { deinitCalledForTester1 = true }
            let tester2 = LeakTester(id: 2) { deinitCalledForTester2 = true }
            map.put(key: 1, value: tester1)
            map.put(key: 2, value: tester2)
            XCTAssertNotNil(map.get(key: 1))
            XCTAssertNotNil(map.get(key: 2))
            _ = map.remove(key: 1)
        }
        XCTAssertTrue(deinitCalledForTester1, "Tester1 should be deallocated after removal")
        XCTAssertNotNil(map.get(key: 2))
        map.clear()
        XCTAssertTrue(deinitCalledForTester2, "Tester2 should be deallocated after clearing the map")
    }
    func testDefaultSubscriptExtension() {
            let map = LinkedHashMap<String, Bool>()
            XCTAssertEqual(map["testKey", default: false], false)
            map["testKey", default: false] = true
            XCTAssertEqual(map["testKey", default: false], true)
            var current = map["testKey", default: false]
            current.toggle() 
            map["testKey", default: false] = current
            XCTAssertEqual(map["testKey", default: false], false)
        }
}
