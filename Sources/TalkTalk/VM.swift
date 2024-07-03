//
//  VM.swift
//  
//
//  Created by Pat Nakajima on 6/30/24.
//

public enum InterpretResult {
	case ok,
			 compileError,
			 runtimeError
}

public struct VM<Output: OutputCollector>: ~Copyable {
	var output: Output
	var ip: UnsafeMutablePointer<Byte>?
	var stack: UnsafeMutablePointer<Value>
	var stackTop: UnsafeMutablePointer<Value>
	var globals: [String: Value] = [:]

	static func run(source: String, output: Output) -> InterpretResult {
		var vm = VM(output: output)
		var compiler = Compiler(source: source)

		do {
			try compiler.compile()
		} catch {
			for error in compiler.errors {
				output.print(error.description)
			}

			return .compileError
		}

		return vm.run(chunk: &compiler.compilingChunk)
	}

	public init(output: Output = StdoutOutput()) {
		self.output = output
		self.stack = UnsafeMutablePointer<Value>.allocate(capacity: 256)
		self.stack.initialize(repeating: .nil, count: 256)
		self.stackTop = UnsafeMutablePointer<Value>(stack)
		self.stackTop.initialize(repeating: .nil, count: 256)
	}

	mutating func initVM() {
		stackReset()
	}

	mutating func stackReset() {
		stackTop = UnsafeMutablePointer<Value>(stack)
	}

	mutating func stackPush(_ value: Value) {
		if stackTop - stack >= 256 {
			fatalError("Stack level too deep.") // TODO: Just grow the stack babyyyyy
		}

		stackTop.pointee = value
		stackTop += 1
	}

	mutating func stackPop() -> Value {
		stackTop -= 1
		return stackTop.pointee
	}

	mutating func stackDebug() {
		if stack == stackTop { return }
		output.debug("\t\t\t\tStack: ", terminator: "")
		if stack < stackTop {
			for slot in stack..<stackTop {
				output.debug("[\(slot.pointee.description)]", terminator: "")
			}
		} else {
			output.print("Stack is in invalid state.")
		}
		output.debug()
	}

	public mutating func run(source: String) -> InterpretResult {
		var compiler = Compiler(source: source)
		do {
			try compiler.compile()
		} catch {
			return .compileError
		}

		var chunk = compiler.compilingChunk
		return run(chunk: &chunk)
	}

	public mutating func run(chunk: inout Chunk) -> InterpretResult {
		self.ip = chunk.code.storage

		while true {
			#if DEBUGGING
			var disassembler = Disassembler(output: output)
			disassembler.report(byte: ip!, in: chunk)
			stackDebug()
			#endif

			let byte = readByte()
			guard let opcode = Opcode(rawValue: byte) else {
				print("Unknown opcode: \(byte)")
				return .runtimeError
			}

			switch opcode {
			case .return:
				return .ok
			case .negate:
				stackPush(-stackPop())
			case .constant:
				stackPush(readConstant(in: chunk))
			case .add:
				let b = stackPop()
				let a = stackPop()
				stackPush(a + b)
			case .subtract:
				let b = stackPop()
				let a = stackPop()
				stackPush(a - b)
			case .multiply:
				let b = stackPop()
				let a = stackPop()
				stackPush(a * b)
			case .divide:
				let b = stackPop()
				let a = stackPop()
				stackPush(a / b)
			case .nil:
				stackPush(.nil)
			case .true:
				stackPush(.bool(true))
			case .false:
				stackPush(.bool(false))
			case .not:
				stackPush(stackPop().not())
			case .equal:
				let a = stackPop()
				let b = stackPop()
				stackPush(.bool(a == b))
			case .notEqual:
				let a = stackPop()
				let b = stackPop()
				stackPush(.bool(a != b))
			case .pop:
				_ = stackPop()
			case .print:
				output.print(stackPop().description)
			case .defineGlobal:
				let name = chunk.constants.read(byte: readByte()).as(String.self)
				globals[name] = stackPop()
			case .getGlobal:
				let name = readString(in: chunk)
				guard let value = globals[name] else {
					output.debug("Undefined variable '\(name)' \(globals.debugDescription)")
					output.print("Error: Undefined variable '\(name)'")
					return .runtimeError
				}
				stackPush(value)
			case .setGlobal:
				let name = chunk.constants.read(byte: readByte()).as(String.self)
				if globals[name] == nil {
					runtimeError("Undefined variable \(name).")
					return .runtimeError
				}

				globals[name] = peek()
			case .getLocal:
				let slot = readByte()
				stackPush(stack[Int(slot)])
			case .setLocal:
				let slot = readByte()
				stack[Int(slot)] = peek()
			}
		}
	}

	mutating func readString(in chunk: borrowing Chunk) -> String {
		return chunk.constants.read(byte: readByte()).as(String.self)
	}

	mutating func readConstant(in chunk: borrowing Chunk) -> Value {
		(chunk.constants.storage + UnsafeMutablePointer<Value>.Stride(readByte())).pointee
	}

	mutating func readByte() -> Byte {
		guard let ip else {
			return .min
		}

		defer {
			self.ip = ip.successor()
		}

		return ip.pointee
	}

	func peek(_ offset: Int = 0) -> Value {
		(stackTop + offset - 1).pointee
	}

	func runtimeError(_ message: String) {
		output.print("Runtime Error: \(message)")
	}

	deinit {
		// I don't think I have to deallocate stackTop since it only
		// refers to memory contained in stack? Same with ip?
		stack.deallocate()
	}
}
