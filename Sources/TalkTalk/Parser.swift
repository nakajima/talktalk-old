//
//  Parser.swift
//
//
//  Created by Pat Nakajima on 7/1/24.
//
public final class Parser {
	enum Precedence: Byte, Comparable {
		static func < (lhs: Parser.Precedence, rhs: Parser.Precedence) -> Bool {
			lhs.rawValue < rhs.rawValue
		}

		static func + (lhs: Precedence, rhs: Byte) -> Precedence {
			Precedence(rawValue: lhs.rawValue + rhs) ?? .any
		}

		case none,
		     assignment, // =
		     or, // ||
		     and, // &&
		     equality, // == !=
		     comparison, // < > <= >=
		     term, // + -
		     factor, // * /
		     unary, // ! -
		     call, // . ()
		     primary,

		     any
	}

	public struct Error: Swift.Error {
		var token: Token
		public var message: String

		public func description(in compiler: Compiler) -> String {
			"""
			\(message) at \(token.start), line: \(token.line)

			\t\(compiler.parser.line(token.line))

			"""
		}
	}

	var lexer: Lexer
	var current: Token!
	var previous: Token!
	var errors: [Error] = []

	init(lexer: consuming Lexer) {
		let first = lexer.next()
		self.current = first
		self.lexer = lexer
	}

	func skip(_ kind: Token.Kind) {
		while check(kind), current.kind != .eof {
			advance()
		}
	}

	func skip(_ kinds: Token.Kinds) {
		while check(kinds), current.kind != .eof {
			advance()
		}
	}

	func advance() {
		previous = current
		while true {
			current = lexer.next()

			if case let .error(message) = current.kind {
				error(at: current, message)
				continue
			}

			break
		}
	}

	func match(_ kind: Token.Kind) -> Bool {
		if !check(kind) {
			return false
		}

		advance()

		return true
	}

	func match(_ kinds: Token.Kinds) -> Bool {
		if check(kinds) {
			advance()
			return true
		}

		return false
	}

	func check(_ kind: Token.Kind) -> Bool {
		return current.kind == kind
	}

	func check(_ kinds: Token.Kinds) -> Bool {
		return kinds.contains(current.kind)
	}

	func consume(_ kinds: Token.Kinds, _: String) {
		if kinds.contains(current.kind) {
			advance()
			return
		}

		let kinds = kinds.map { "\($0)".components(separatedBy: ".").last! }.joined(separator: ", ")
		error(at: current, "Unexpected token: \(current.description(in: lexer.source)). Expected: \(kinds).")
	}

	func consume(_ kind: Token.Kind, _: String) {
		if current.kind == kind {
			advance()
			return
		}

		let kind = "\(kind)".components(separatedBy: ".").last!
		error(at: current, "Unexpected token: \(current.description(in: lexer.source)). Expected: \(kind).")
	}

	func line(_ number: Int) -> String {
		let lines = String(lexer.source).components(separatedBy: "\n")
		if number >= lines.count {
			return "EOF"
		} else {
			return lines[number]
		}
	}

	func error(at token: Token, _ message: String) {
		errors.append(Error(token: token, message: message))
	}
}
