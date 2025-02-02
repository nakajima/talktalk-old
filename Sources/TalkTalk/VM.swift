//
//  VM.swift
//
//
//  Created by Pat Nakajima on 6/30/24.
//
import Foundation

public enum InterpretResult {
	case ok,
	     compileError,
	     runtimeError
}

final class OpenUpvalues {
	var value: Value
	var next: OpenUpvalues?

	init(value: Value) {
		self.value = value
	}
}

public struct VM<Output: OutputCollector> {
	var output: Output
	var stack = Stack<Value>(capacity: 256)
	var frames = Stack<CallFrame>(capacity: 256)
	var globals: [Int: Value] = [:]
	var openUpvalues: OpenUpvalues?

	var result: Value?

	var chunk: Chunk!
	var currentFrame: CallFrame!
	var ip: Int = 0

	public static func run(source: String, output: Output) -> InterpretResult {
		var vm = VM(output: output)
		let compiler = Compiler(source: source)

		do {
			try compiler.compile()
		} catch {
			output.print(
				compiler.collectErrors()
					.map { $0.description(in: compiler) }
					.joined(separator: "\n")
			)
			return .compileError
		}

		return vm.run(function: compiler.function)
	}

	public init(output: Output = StdoutOutput()) {
		self.output = output
		for (name, function) in Native.list {
			globals[name.hashValue] = .native(function.init().name)
		}
	}

	mutating func initVM() {
		stack.reset()
	}

	mutating func stackDebug(into output: (any OutputCollector)? = nil) {
		let output: any OutputCollector = output ?? self.output

		if stack.isEmpty { return }
		output.debug(String(repeating: " ", count: 9), terminator: "")
		for slot in stack.entries() {
			output.debug("[ \(slot.description) ]", terminator: "")
		}
		output.debug()
	}

	public mutating func run(source: String) -> InterpretResult {
		// TODO: Handle actual imports
		let compiler = Compiler(source: source)

		do {
			try compiler.compile()
		} catch {
			return .compileError
		}

		return run(function: compiler.function)
	}

	@inline(__always)
	mutating func restoreFrame(from frame: CallFrame) {
		ip = frame.lastIP
		currentFrame = frames.peek()
		chunk = currentFrame.closure.function.chunk
	}

	private mutating func run(function: Function) -> InterpretResult {
		let rootClosure = Closure(function: function)
		stack.push(.closure(rootClosure))
		return run(closure: rootClosure)
	}

	private mutating func run(closure rootClosure: Closure) -> InterpretResult {
		_ = call(rootClosure, argCount: 0)

		while true {
			#if DEBUGGING
				stackDebug()
				Disassembler.dump(chunk: chunk, ip: ip, into: output)
			#endif

			let byte = readByte()
			guard let opcode = Opcode(rawValue: byte) else {
				output.print("Unknown opcode: \(byte)")
				return .runtimeError
			}

			switch opcode {
			case .return:
				let result = stack.pop()
				let frame = frames.pop()

				// closeUpvalues()

				if frames.isEmpty {
					self.result = result
					return .ok
				}

				while stack.size > frame.stackOffset {
					_ = stack.pop()
				}

				// Append the return value
				stack.push(result)

				restoreFrame(from: frame)
			case .negate:
				stack.push(-stack.pop())
			case .constant:
				stack.push(readConstant())
			case .add:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a + b)
			case .subtract:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a - b)
			case .multiply:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a * b)
			case .divide:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a / b)
			case .less:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a < b)
			case .greater:
				let b = stack.pop()
				let a = stack.pop()
				stack.push(a > b)
			case .nil:
				stack.push(.nil)
			case .true:
				stack.push(.bool(true))
			case .false:
				stack.push(.bool(false))
			case .not:
				stack.push(stack.pop().not())
			case .equal:
				let a = stack.pop()
				let b = stack.pop()
				stack.push(.bool(a == b))
			case .notEqual:
				let a = stack.pop()
				let b = stack.pop()
				stack.push(.bool(a != b))
			case .pop:
				_ = stack.pop()
			case .print:
				output.print(stack.pop().description)
			case .defineGlobal:
				let name = readString()
				globals[name.hashValue] = stack.peek()
				_ = stack.pop()
			case .getGlobal:
				let name = readString()
				guard let value = globals[name.hashValue] else {
					runtimeError("Undefined global variable '\(name)' \(globals.debugDescription)")
					return .runtimeError
				}
				stack.push(value)
			case .setGlobal:
				let name = readString()
				if globals[name.hashValue] == nil {
					runtimeError("Undefined global variable \(name).")
					return .runtimeError
				}

				globals[name.hashValue] = stack.peek()
			case .getLocal:
				let slot = readByte()
				stack.push(
					currentFrame.stack[Int(slot)]
				)
			case .setLocal:
				let slot = readByte()
				currentFrame.stack[Int(slot)] = stack.peek()
			case .uninitialized:
				runtimeError("Unitialized instruction cannot be run (maybe it's a constant?): \(stack.peek().description)")
			case .jump:
				let offset = readShort()
				ip += Int(offset)
			case .jumpIfFalse:
				let offset = readShort()
				let isTrue = stack.peek().as(Bool.self)
				if !isTrue {
					ip += Int(offset)
				}
			case .loop:
				let offset = readShort()
				ip -= Int(offset)
			case .call:
				let argCount = readByte()
				if !callValue(stack.peek(offset: Int(argCount)), argCount) {
					return .runtimeError
				}
			case .closure:
				let function = readConstant().as(Function.self)
				var closure = Closure(function: function)

				stack.push(.closure(closure))

				for i in 0 ..< closure.function.upvalueCount {
					let isLocal = readByte() == 1
					let index = Int(readByte())

					if isLocal {
						closure.upvalues[i] = captureUpvalue(currentFrame.stack[index])
					} else {
						// TODO: the -1 here doesn't smell right to me but it got the tests passing?
						closure.upvalues[i] = currentFrame.closure.upvalues[index]
					}
				}
			case .getUpvalue:
				let slot = readByte()
				let upvalue = currentFrame.closure.upvalues[Int(slot)]!
				let unwrapped = upvalue
				stack.push(unwrapped)
			case .setUpvalue:
				let slot = readByte()
				currentFrame.closure.upvalues[Int(slot)] = stack.peek(offset: 0)
			case .closeUpvalue:
				closeUpvalues()
				_ = stack.pop()
			case .class:
				stack.push(
					.class(
						Class(name: readString())
					)
				)
			case .getProperty:
				let property = readString()
				let callee = stack.pop().as(ClassInstance.self)

				if let value = callee.get(property) {
					stack.push(value)
				} else if let computed = callee.klass.lookup(computedProperty: property) {
					stack.push(.classInstance(callee))
					if !call(computed, argCount: 0) {
						return .runtimeError
					}
					stack.pop()
//					restoreFrame(from: frames.pop())
				} else if !bindMethod(callee.klass, named: property) {
					runtimeError("No property named `\(property)` for \(callee)")
				}
			case .setProperty:
				let instance = stack.peek(offset: 1).as(ClassInstance.self)
				let property = readString()
				instance.set(property, stack.peek())

				// Get the value
				let value = stack.pop()

				// Pop off the instance
				stack.pop()

				// Return the value
				stack.push(value)
			case .method:
				defineMethod(named: readString())
			case .computedProperty:
				defineComputedProperty(named: readString())
			case .invoke:
				let method = readString()
				let argCount = readByte()

				if !invoke(method, argCount) {
					return .runtimeError
				}
			case .inherit:
				// TODO: Don't make this crash, just return a runtime error? (preferably a compiler err)
				let superclass = stack.peek(offset: 1).as(Class.self)
				let subclass = stack.peek().as(Class.self)

				// This only works while classes can't be extended:
				for (name, closure) in superclass.methods {
					subclass.define(method: closure, as: name)
				}

				stack.pop()
			case .getSuper:
				let name = readString()
				let superclass = stack.pop().as(Class.self)
				if !bindMethod(superclass, named: name) {
					return .runtimeError
				}
			case .invokeSuper:
				let method = readString()
				let argCount = readByte()
				let superclass = stack.pop().as(Class.self)

				if !invokeFromClass(superclass, method, argCount) {
					return .runtimeError
				}
			case .arrayLiteral:
				let argCount = readByte()
				let elements = stack.pop(count: Int(argCount)).reversed()
				let klass = globals["Array".hashValue]!.as(Class.self)

				stack.push(.array(.init(elements)))
				stack.push(.int(Int(argCount)))

				if !callValue(.class(klass), 2) {
					return .runtimeError
				}
			}
		}
	}

	private mutating func invoke(_ name: String, _ argCount: Byte) -> Bool {
		let receiver = stack.peek(offset: Int(argCount))
		let instance = receiver.as(ClassInstance.self)

		if let property = instance.get(name) {
			stack[stack.size - 1 - Int(argCount)] = .classInstance(instance)
			return callValue(property, argCount)
		}

		return invokeFromClass(instance.klass, name, argCount)
	}

	private mutating func invokeFromClass(_ klass: Class, _ name: String, _ argCount: Byte) -> Bool {
		if let method = klass.lookup(method: name) {
			return call(method, argCount: argCount)
		} else {
			runtimeError("Undefined property \(name) for \(klass.name)")
			return false
		}
	}

	private mutating func defineMethod(named name: String) {
		let method = stack.peek().as(Closure.self)
		let klass = stack.peek(offset: 1).as(Class.self)

		klass.define(method: method, as: name)

		stack.pop()
	}

	private mutating func defineComputedProperty(named name: String) {
		let property = stack.peek().as(Closure.self)
		let klass = stack.peek(offset: 1).as(Class.self)

		klass.define(computedProperty: property, as: name)

		stack.pop()
	}

	private mutating func bindMethod(_ klass: Class, named name: String) -> Bool {
		if let method = klass.lookup(method: name) {
			let callee = stack.peek().as(ClassInstance.self)

			// Pop the callee (instance) off the stack
			stack.pop()

			// Add the bound method
			stack.push(.boundMethod(callee, method))

			return true
		} else {
			return false
		}
	}

	private mutating func captureUpvalue(_ local: Value) -> Value {
		var prevUpvalue: OpenUpvalues?
		var upvalue = openUpvalues

		// If we were using actual C we could check to see if the upvalue's
		// location is  greater than the local's but we're not managing
		// memory so ¯\_(ツ)_/¯
		while let nextUpvalue = upvalue {
			if nextUpvalue.value == local {
				return nextUpvalue.value
			}

			prevUpvalue = nextUpvalue
			upvalue = nextUpvalue.next
		}

		let createdUpvalue = local
		if let prevUpvalue {
			prevUpvalue.next = OpenUpvalues(value: createdUpvalue)
		} else {
			openUpvalues = OpenUpvalues(value: createdUpvalue)
		}

		return createdUpvalue
	}

	mutating func eval(closure: Closure, in instance: ClassInstance) -> Value {
		var vm = VM(output: output)
		vm.stack.push(.closure(closure))
		vm.stack.push(.classInstance(instance))
		if vm.run(closure: closure) == .ok {
			return vm.result ?? .nil
		} else {
			runtimeError("Error evaluating closure")
			return .nil
		}
	}

	// I don't think this makes sense without pointers?
	func closeUpvalues() {
//		var nextUpvalue = openUpvalues
//		while let upvalue = nextUpvalue {
//			upvalue.closed
//		}
	}

	@inline(__always)
	private mutating func callValue(_ callee: Value, _ argCount: Byte) -> Bool {
		switch callee {
		case let .closure(closure):
			return call(closure, argCount: argCount)
		case let .class(klass):
			let instance = ClassInstance(klass: klass, fields: [:])

			if let initializer = klass.lookup(method: "init") {
				stack[stack.size - Int(argCount) - 1] = .classInstance(instance)

				return call(initializer, argCount: argCount)
			} else if argCount > 0 {
				runtimeError("Expected 0 arguments to \(klass.name) init, got \(argCount)")
				return false
			} else {
				stack.pop() // Remove the class
				stack.push(.classInstance(instance))
				return true
			}
		case let .boundMethod(callee, closure):
			stack[stack.size - Int(argCount) - 1] = .classInstance(callee)
			return call(closure, argCount: argCount)
		case let .native(name):
			guard let instance = Native.list[name]?.init() else {
				return false
			}

			if instance.arity != argCount {
				runtimeError("Expected \(instance.arity) arguments for \(name)(), got \(argCount)")
				return false
			}

			let args = stack.pop(count: Int(argCount))
			let result = instance.call(arguments: args, in: &self)
			stack.push(result)
			return true
		case let .array(array):
			if argCount != 1 {
				runtimeError("Expected 1 argument to array subscript, got \(argCount)")
				return false
			}

			let index = stack.pop().as(Int.self)
			stack.pop() // pop the array

			if index >= array.storage.count || index < 0 {
				stack.push(.nil)
			} else {
				stack.push(array.storage[index])
			}

			return true
		case let .classInstance(instance):
			if let subscriptFunc = instance.klass.lookup(method: "subscript") {
				return call(subscriptFunc, argCount: 1)
			} else {
				runtimeError("\(instance) does not have any subscripts")
				return false
			}
		default:
			runtimeError("\(callee) not callable")
			return false // Non-callable type
		}
	}

	@inline(__always)
	mutating func call(_ closure: Closure, argCount: Byte) -> Bool {
		chunk = closure.function.chunk

		let fn = closure.function
		if argCount != fn.arity {
			runtimeError("Expected \(fn.arity) arguments for \(fn.name)(), got \(argCount)")
			return false
		}

		if frames.size > 255 {
			runtimeError("Stack level too deep")
			return false
		}

		var frame = CallFrame(
			closure: closure,
			stack: stack,
			stackOffset: stack.size - Int(argCount) - 1
		)

		// Stash the current IP on the frame to be restored on return
		frame.lastIP = ip

		// Set the IP back to zero for the current frame
		ip = 0

		frames.push(frame)
		currentFrame = frame

		return true
	}

	@inline(__always)
	private mutating func readShort() -> UInt16 {
		// Move two bytes, because we're gonna read... two bytes
		ip += 2

		let a = chunk.code[ip - 2]
		let b = chunk.code[ip - 1]

		// Grab those two bytes from the chunk's code and build
		// a 16 bit (two byte, nice) unsigned int.
		return UInt16((a << 8) | b)
	}

	@inline(__always)
	private mutating func readString() -> String {
		return chunk.constants.read(byte: readByte()).as(String.self)
	}

	@inline(__always)
	private mutating func readConstant() -> Value {
		chunk.constants[Int(readByte())]
	}

	@inline(__always)
	private mutating func readByte() -> Byte {
		return chunk.code[ip++]
	}

	private mutating func runtimeError(_ message: String) {
		output.print("------------------------------------------------------------------")
		output.print("Runtime Error: \(message)")
		output.print("------------------------------------------------------------------")
		stackDebug()
		var i = frames.size - 1
		while i >= 0 {
			let frame = frames[i]
			let function = frame.closure.function
			let instruction = function.chunk.code[ip - 1]
			output.print("\t[line \(function.chunk.lines[Int(instruction)])] in \(function.name)()")
			i -= 1
		}

		stack.reset()
	}

	mutating func dump(into output: some OutputCollector = StdoutOutput()) {
		Disassembler.dump(chunk: chunk, into: output, highlight: ip - 1)
		stackDebug(into: output)
		output.print("Constants:")
		for (i, constant) in chunk.constants.enumerated() {
			output.print("\(i): \(constant)")
		}
	}
}
