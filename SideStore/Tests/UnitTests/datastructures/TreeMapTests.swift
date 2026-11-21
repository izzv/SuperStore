//
//  TreeMapTests.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import XCTest

class TreeMapTests: XCTestCase {
    func testInsertionAndRetrieval() {
        let map = TreeMap<Int, String>()
        XCTAssertNil(map[10])
        map[10] = "ten"
        XCTAssertEqual(map[10], "ten")
        map[5] = "five"
        map[15] = "fifteen"
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map[5], "five")
        XCTAssertEqual(map[15], "fifteen")
    }
    func testUpdateValue() {
        let map = TreeMap<Int, String>()
        map[10] = "ten"
        let oldValue = map.insert(key: 10, value: "TEN")
        XCTAssertEqual(oldValue, "ten")
        XCTAssertEqual(map[10], "TEN")
        XCTAssertEqual(map.count, 1)
    }
    func testDeletion() {
        let map = TreeMap<Int, String>()
        map[20] = "twenty"
        map[10] = "ten"
        map[30] = "thirty"
        let removedLeaf = map.remove(key: 10)
        XCTAssertEqual(removedLeaf, "ten")
        XCTAssertNil(map[10])
        XCTAssertEqual(map.count, 2)
        map[25] = "twenty-five"
        map[27] = "twenty-seven" 
        let removedOneChild = map.remove(key: 25)
        XCTAssertEqual(removedOneChild, "twenty-five")
        XCTAssertNil(map[25])
        XCTAssertEqual(map.count, 3)
        map[40] = "forty"
        map[35] = "thirty-five"
        map[45] = "forty-five"
        let removedTwoChildren = map.remove(key: 40)
        XCTAssertEqual(removedTwoChildren, "forty")
        XCTAssertNil(map[40])
        XCTAssertEqual(map.count, 5)
    }
    func testDeletionOfRoot() {
        let map = TreeMap<Int, String>()
        map[50] = "fifty"
        map[30] = "thirty"
        map[70] = "seventy"
        let removedRoot = map.remove(key: 50)
        XCTAssertEqual(removedRoot, "fifty")
        XCTAssertNil(map[50])
        XCTAssertEqual(map.keys, [30, 70])
    }
    func testSortedIteration() {
        let map = TreeMap<Int, String>()
        let keys = [20, 10, 30, 5, 15, 25, 35]
        for key in keys {
            map[key] = "\(key)"
        }
        let sortedKeys = map.keys
        XCTAssertEqual(sortedKeys, keys.sorted())
        var previous: Int? = nil
        for (key, value) in map {
            if let prev = previous {
                XCTAssertLessThanOrEqual(prev, key)
            }
            previous = key
            XCTAssertEqual(value, "\(key)")
        }
    }
    func testRemoveAll() {
        let map = TreeMap<Int, String>()
        for i in 0..<100 {
            map[i] = "\(i)"
        }
        XCTAssertEqual(map.count, 100)
        map.removeAll()
        XCTAssertEqual(map.count, 0)
        XCTAssertTrue(map.isEmpty)
    }
    func testBalancing() {
        let map = TreeMap<Int, Int>()
        for i in 1...1000 {
            map[i] = i
        }
        var expected = 1
        for (key, value) in map {
            XCTAssertEqual(key, expected)
            XCTAssertEqual(value, expected)
            expected += 1
        }
        XCTAssertEqual(expected - 1, 1000)
        for i in stride(from: 1, through: 1000, by: 2) {
            _ = map.remove(key: i)
        }
        let expectedEvenKeys = (1...1000).filter { $0 % 2 == 0 }
        XCTAssertEqual(map.keys, expectedEvenKeys)
    }
    func testNonExistentDeletion() {
        let map = TreeMap<Int, String>()
        map[10] = "ten"
        let removed = map.remove(key: 20)
        XCTAssertNil(removed)
        XCTAssertEqual(map.count, 1)
    }
    func testDuplicateInsertion() {
        let map = TreeMap<String, String>()
        map["a"] = "first"
        XCTAssertEqual(map["a"], "first")
        let oldValue = map.insert(key: "a", value: "second")
        XCTAssertEqual(oldValue, "first")
        XCTAssertEqual(map["a"], "second")
        XCTAssertEqual(map.count, 1)
    }
}
