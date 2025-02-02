//
//  StackTests.swift
//
//
//  Created by Pat Nakajima on 7/5/24.
//
@testable import TalkTalk
import Testing

struct StackTests {
	class Item {
		var value: String

		init(value: String) {
			self.value = value
		}

		deinit {
			print("Item.value = \(value)")
		}
	}

	@Test("Basics") func peek() {
		var stack = Stack<Item>(capacity: 16)
		stack.push(Item(value: "3"))
		stack.push(Item(value: "2"))
		stack.push(Item(value: "1"))

		#expect(stack.entries().map(\.value) == ["3", "2", "1"])

		#expect(stack.size == 3)
		#expect(stack.peek().value == "1")

		#expect(stack.pop().value == "1")
		#expect(stack.peek().value == "2")
		#expect(stack.size == 2)
	}

	@Test("Pop many") func popmany() {
		var stack = Stack<Item>(capacity: 16)
		stack.push(Item(value: "3"))
		stack.push(Item(value: "2"))
		stack.push(Item(value: "1"))

		#expect(stack.pop(count: 2).map(\.value) == ["1", "2"])
	}

	@Test("Bench") func bench() {
		var stack = Stack<Int>(capacity: 10_000_001)
		for i in 0 ..< 10_000_000 {
			stack.push(i)
			_ = stack.size
			_ = stack.peek()
			_ = stack.pop()
		}
	}
}
