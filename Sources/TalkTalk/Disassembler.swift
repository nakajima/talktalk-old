//
//  Debug.swift
//
//
//  Created by Pat Nakajima on 6/30/24.
//
struct ConstantMetadata: Disassembler.Metadata {
	var byte: Byte
	var value: Value

	var description: String {
		"\(byte) \(value.description)"
	}
}

struct ByteMetadata: Disassembler.Metadata {
	var byte: Byte

	var description: String {
		"Byte: \(byte)"
	}
}

struct ClosureMetadata: Disassembler.Metadata {
	var function: Function
	var upvalues: [Upvalue]
	var constant: Byte

	var description: String {
		var parts = ["\(constant) <fn \(function.name)>"]
		for upvalue in upvalues {
			parts.append(
				String(repeating: " ", count: 8) + " | \(upvalue.index) \(upvalue.isLocal ? "local" : "up value")"
			)
		}

		return parts.joined(separator: "\n")
	}
}

struct JumpMetadata: Disassembler.Metadata {
	var offset: Int
	var sign: Int
	var jump: Int

	var description: String {
		"\(offset) -> \(offset + 3 + sign * jump)"
	}
}

struct InvokeMetadata: Disassembler.Metadata {
	var name: String
	var arity: Byte

	var description: String {
		".\(name) \(arity)"
	}
}

struct ArrayMetadata: Disassembler.Metadata {
	var count: Int

	var description: String {
		"count \(count)"
	}
}

struct Disassembler {
	protocol Metadata: Equatable, CustomStringConvertible {}

	struct Instruction {
		var offset: Int
		var opcode: String
		var metadata: (any Metadata)?
		var line: Int
		var isSameLine: Bool
		var isCurrent: Bool = false

		var description: String {
			let lineString = isSameLine ? "  |" : String(format: "% 3d", line)
			let parts = [
				String(format: "%04d", offset),
				lineString,
				opcode,
				metadata?.description ?? "",
			]

			return parts.joined(separator: " ")
		}
	}

	static var header: String {
		"POS\t\tLINE\tOPERATION"
	}

	var name = ""
	var instructions: [Instruction] = []
	var chunk: Chunk
	var offset = 0

	init(name: String = "", chunk: Chunk) {
		self.name = name
		self.chunk = chunk
	}

	static func dump(chunk: Chunk, into output: some OutputCollector, highlight: Int? = nil) {
		var disassembler = Disassembler(chunk: chunk)

		if highlight != nil {
			print("  ", terminator: "")
		}

		output.print(Self.header)
		while let instruction = disassembler.nextInstruction() {
			if let highlight {
				output.print((highlight == instruction.offset ? "> " : "  ") + instruction.description)
			} else {
				output.print(instruction.description)
			}
		}
	}

	static func dump(chunk: Chunk, ip: Int, into output: some OutputCollector) {
		var disassembler = Disassembler(chunk: chunk)
		disassembler.offset = ip
		if let out = disassembler.nextInstruction()?.description {
			output.debug(out)
		} else {
			output.debug("No instruction at \(ip)")
		}
	}

	mutating func nextInstruction() -> Instruction? {
		if offset >= chunk.count {
			return nil
		}

		let instruction = chunk.code[offset]
		let opcode = Opcode(rawValue: instruction)

		switch opcode {
		case .constant:
			return constantInstruction("OP_CONSTANT")
		case .defineGlobal, .getGlobal, .setGlobal:
			return constantInstruction(opcode!.description)
		case .getLocal, .setLocal, .call:
			return byteInstruction(
				opcode!.description
			)
		case .jump, .jumpIfFalse:
			return jumpInstruction(opcode!.description, sign: 1)
		case .loop:
			return jumpInstruction(opcode!.description, sign: -1)
		case .getUpvalue, .setUpvalue:
			return byteInstruction(opcode!.description)
		case .closure:
			return closureInstruction()
		case .class:
			return constantInstruction("OP_CLASS")
		case .getProperty, .setProperty:
			return constantInstruction(opcode!.description)
		case .method:
			return constantInstruction(opcode!.description)
		case .computedProperty:
			return constantInstruction(opcode!.description)
		case .invoke, .invokeSuper:
			return invokeInstruction()
		case .getSuper:
			return constantInstruction("OP_GET_SUPER")
		case .arrayLiteral:
			return arrayInstruction()
		default:
			return simpleInstruction(opcode!.description)
		}
	}

	private mutating func arrayInstruction() -> Instruction {
		let originalOffset = offset

		let argCount = chunk.code[++offset]

		defer {
			offset++
		}

		return Instruction(
			offset: originalOffset,
			opcode: "OP_ARRAY_LITERAL",
			metadata: ArrayMetadata(count: Int(argCount)),
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func simpleInstruction(_ label: String) -> Instruction {
		defer {
			offset += 1
		}

		return Instruction(
			offset: offset,
			opcode: label,
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func closureInstruction() -> Instruction {
		let start = offset
		let line = line
		let isSameLine = isSameLine
		_ = offset++
		let constant = chunk.code[offset++]
		let function = chunk.constants[Int(constant)].as(Function.self)
		var upvalues: [Upvalue] = []

		for _ in 0 ..< function.upvalueCount {
			let isLocal = chunk.code[offset++]
			let index = chunk.code[offset++]

			upvalues.append(Upvalue(isLocal: isLocal != 0, index: index))
		}

		return Instruction(
			offset: start,
			opcode: "OP_CLOSURE",
			metadata: ClosureMetadata(
				function: function,
				upvalues: upvalues,
				constant: constant
			),
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func byteInstruction(_ label: String) -> Instruction {
		defer {
			offset += 2
		}

		let byte = chunk.code[offset + 1]
		let instruction = Instruction(
			offset: offset,
			opcode: label,
			metadata: ByteMetadata(byte: byte),
			line: line,
			isSameLine: isSameLine
		)

		return instruction
	}

	private mutating func constantInstruction(_ label: String) -> Instruction {
		defer {
			offset += 2
		}

		let constant = chunk.code[offset + 1]
		let value = chunk.constants[Int(constant)]

		return Instruction(
			offset: offset,
			opcode: label,
			metadata: ConstantMetadata(byte: constant, value: value),
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func jumpInstruction(_ label: String, sign: Int) -> Instruction {
		var jump = Int(chunk.code[offset + 1] << 8)
		jump |= Int(chunk.code[offset + 2])

		defer {
			offset += 3
		}

		return Instruction(
			offset: offset,
			opcode: label,
			metadata: JumpMetadata(offset: offset, sign: sign, jump: jump),
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func invokeInstruction() -> Instruction {
		defer {
			offset += 3
		}

		let constant = chunk.code[offset + 1]
		let name = chunk.constants[Int(constant)]
		let argCount = chunk.code[offset + 2]

		return Instruction(
			offset: offset,
			opcode: "OP_INVOKE",
			metadata: InvokeMetadata(
				name: name.as(String.self),
				arity: argCount
			),
			line: line,
			isSameLine: isSameLine
		)
	}

	private mutating func append(_ instruction: Instruction) {
		instructions.append(instruction)
	}

	var line: Int {
		chunk.lines[offset]
	}

	var isSameLine: Bool {
		offset > 0 && line == chunk.lines[offset - 1]
	}
}

extension Disassembler: Sequence {
	struct Iterator: IteratorProtocol {
		var disassembler: Disassembler

		init(disassembler: Disassembler) {
			self.disassembler = disassembler
		}

		mutating func next() -> Instruction? {
			disassembler.nextInstruction()
		}
	}

	func makeIterator() -> Iterator {
		Iterator(disassembler: self)
	}
}
