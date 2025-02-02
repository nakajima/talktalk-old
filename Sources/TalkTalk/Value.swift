//
//  Value.swift
//
//
//  Created by Pat Nakajima on 6/30/24.
//

struct InternalArray: Hashable {
	var storage: DynamicArray<Value>

	init(_ elements: some Collection<Value>) {
		self.storage = DynamicArray(elements)
	}
}

// Values are anything that can be passed around or defined
enum Value: Equatable, Hashable {
	static func == (lhs: Value, rhs: Value) -> Bool {
		lhs.equals(rhs)
	}

	case error(String),
	     bool(Bool),
	     `nil`,
	     int(Int),
	     string(String),
	     closure(Closure),
	     function(Function),
	     native(String),
	     `class`(Class),
	     classInstance(ClassInstance),
	     boundMethod(ClassInstance, Closure),
	     array(InternalArray)

	@inline(__always)
	func equals(_ other: Value) -> Bool {
		switch (self, other) {
		case let (.error(string), .error(other)):
			return string == other
		case let (.bool(bool), .bool(other)):
			return bool == other
		case (.nil, .nil):
			return true
		case let (.int(double), .int(other)):
			return double == other
		case let (.string(string), .string(other)):
			return string == other
		case let (.function(function), .function(other)):
			return function == other
		case let (.native(nativeFunction), .native(other)):
			return nativeFunction == other
		default:
			return false
		}
	}

	func `as`<T>(_ type: T.Type) -> T {
		switch type {
		case is Bool.Type:
			if case let .bool(bool) = self {
				return bool as! T
			}
		case is Int.Type:
			if case let .int(int) = self {
				return int as! T
			}
		case is String.Type:
			return description as! T
		case is Byte.Type:
			if case let .int(double) = self {
				return Byte(double) as! T
			}
		case is Function.Type:
			if case let .function(function) = self {
				return function as! T
			} else if case let .closure(closure) = self {
				return closure.function as! T
			}
		case is Closure.Type:
			if case let .closure(closure) = self {
				return closure as! T
			}
		case is Class.Type:
			if case let .class(klass) = self {
				return klass as! T
			}
		case is ClassInstance.Type:
			if case let .classInstance(classInstance) = self {
				return classInstance as! T
			}
		case is InternalArray.Type:
			if case let .array(array) = self {
				return array as! T
			}
		default:
			()
		}

		fatalError("\(self) cast to \(T.self) not implemented.")
	}

	var description: String {
		switch self {
		case let .error(msg):
			return "Error: \(msg)"
		case let .bool(bool):
			return "\(bool)"
		case .nil:
			return "nil"
		case let .int(double):
			return "\(double)"
		case let .string(string):
			return string
		case let .function(function):
			return "<\(function.name)>"
		case let .closure(closure):
			return "<\(closure.function.name)>"
		case let .native(native):
			return "<native \(native)>"
		case let .class(klass):
			return "<class \(klass.name)>"
		case let .classInstance(instance):
			return "<\(instance.klass.name) instance>"
		case let .boundMethod(instance, _):
			return "<\(instance) bound method>"
		case let .array(array):
			return "[" + array.storage.map(\.description).joined(separator: ", ") + "]"
		}
	}

	func describe<Output: OutputCollector>(in vm: inout VM<Output>) -> String {
		if case let .classInstance(instance) = self {
			if let prop = instance.get("description") {
				return prop.as(String.self)
			}

			if let computed = instance.klass.lookup(computedProperty: "description") {
				let result = vm.eval(closure: computed, in: instance)
				return result.as(String.self)
			}

			return "INSTANCE: \(description)"
		}

		return description
	}

	func not() -> Value {
		switch self {
		case let .bool(bool):
			.bool(!bool)
		default:
			.error("Cannot negate \(self)")
		}
	}

	static prefix func - (rhs: Value) -> Value {
		switch rhs {
		case let .int(double):
			.int(-double)
		default:
			.error("Cannot negate \(self)")
		}
	}

	static func + (lhs: Value, rhs: Value) -> Value {
		switch lhs {
		case let .int(lhs):
			guard case let .int(rhs) = rhs else {
				return .error("Cannot + \(rhs)")
			}

			return .int(lhs + rhs)
		case let .string(lhs):
			guard case let .string(rhs) = rhs else {
				return .error("Cannot + \(self)")
			}

			return Value.string(lhs + rhs)
		default:
			return .error("Cannot + \(lhs), \(rhs)")
		}
	}

	static func - (lhs: Value, rhs: Value) -> Value {
		guard case let .int(rhs) = rhs else {
			return .error("Cannot - \(rhs)")
		}

		return switch lhs {
		case let .int(lhs):
			.int(lhs - rhs)
		default:
			.error("Cannot - \(lhs) \(rhs)")
		}
	}

	static func * (lhs: Value, rhs: Value) -> Value {
		guard case let .int(rhs) = rhs else {
			return .error("Cannot * \(rhs)")
		}

		return switch lhs {
		case let .int(lhs):
			.int(lhs * rhs)
		default:
			.error("Cannot * \(lhs) \(rhs)")
		}
	}

	static func / (lhs: Value, rhs: Value) -> Value {
		guard case let .int(rhs) = rhs else {
			return .error("Cannot / \(rhs)")
		}

		return switch lhs {
		case let .int(lhs):
			.int(lhs / rhs)
		default:
			.error("Cannot / \(lhs) \(rhs)")
		}
	}

	static func < (lhs: Value, rhs: Value) -> Value {
		guard case let .int(rhs) = rhs else {
			return .error("Cannot < \(rhs)")
		}

		return switch lhs {
		case let .int(lhs):
			.bool(lhs < rhs)
		default:
			.error("Cannot < \(lhs) \(rhs)")
		}
	}

	static func > (lhs: Value, rhs: Value) -> Value {
		guard case let .int(rhs) = rhs else {
			return .error("Cannot > \(rhs)")
		}

		return switch lhs {
		case let .int(lhs):
			.bool(lhs > rhs)
		default:
			.error("Cannot > \(lhs) \(rhs)")
		}
	}
}

extension Value: ExpressibleByIntegerLiteral {
	init(integerLiteral: Float) {
		self = .int(Int(integerLiteral))
	}
}
