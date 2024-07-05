//
//  Stack.swift
//
//
//  Created by Pat Nakajima on 7/3/24.
//

class Stack<Value> {
	var size = 0
	private var storage: [Value] = []

	subscript(_ offset: Int) -> Value {
		get {
			storage[offset]
		}

		set {
			storage[offset] = newValue
		}
	}

	subscript(_ range: Range<Int>) -> ArraySlice<Value> {
		storage[range]
	}

	var isEmpty: Bool {
		size == 0
	}

	var entries: [Value] {
		storage
	}

	func peek(offset: Int = 0) -> Value {
		return storage[size - 1 - offset]
	}

	func push(_ value: Value) {
		storage.append(value)
		size += 1
	}

	func pop() -> Value {
		size -= 1
		return storage.removeLast()
	}

	@discardableResult func pop(count: Int) -> [Value] {
		defer {
			size -= count
		}

		return (0 ..< count).map { _ in storage.removeLast() }
	}

	func last(count: Int) -> ArraySlice<Value> {
		return storage[size - count..<size]
	}

	func reset() {
		size = 0
		storage = []
	}
}
