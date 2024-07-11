//
//  Parser.swift
//
//
//  Created by Pat Nakajima on 7/8/24.
//
public struct ProgramSyntax: Syntax {
	public let position: Int
	public let length: Int

	public var decls: [any Decl] = []

	public var description: String {
		decls.map(\.description).joined(separator: "\n")
	}

	public func accept<Visitor: ASTVisitor>(_ visitor: inout Visitor) -> Visitor.Value {
		visitor.visit(self)
	}
}

struct Parser {
	var errors: [Error] = []
	var lexer: Lexer
	var previous: Token
	var current: Token
	var parserRepeats: [Int: Int] = [:]

	init(lexer: Lexer) {
		self.lexer = lexer
		self.previous = self.lexer.next()
		self.current = previous
	}

	mutating func parse() -> [any Decl] {
		var decls: [any Decl] = []

		while current.kind != .eof {
			skip(.newline)
			decls.append(decl())
		}

		return decls
	}

	mutating func decl() -> any Decl {
		if match(.var) {
			return varDecl()
		}

		if match(.func) {
			return funcDecl()
		}

		return statement()
	}

	mutating func varDecl() -> any Decl {
		let start = previous.start

		guard let identifier = consume(IdentifierSyntax.self) else {
			return ErrorSyntax(token: current, expected: .token(.identifier))
		}

		var expr: (any Expr)?
		if match(.equal) {
			expr = parse(precedence: .assignment)
		}

		return VarDeclSyntax(
			position: start,
			length: current.start - start,
			variable: identifier,
			expr: expr
		)
	}

	mutating func funcDecl() -> FunctionDeclSyntax {
		let position = previous.start
		let name = consume(IdentifierSyntax.self)!

		consume(.leftParen, "Expected '(' before parameter list")
		let parameters = parameterList()

		let body = block()

		return FunctionDeclSyntax(
			position: position,
			length: current.start - position,
			name: name,
			parameters: parameters,
			body: body
		)
	}

	mutating func statement() -> any Stmt {
		if match(.leftBrace) {
			return block()
		}

		let position = current.start
		let expr = parse(precedence: .assignment)

		return ExprStmtSyntax(
			position: current.start,
			length: position - current.start,
			expr: expr
		)
	}

	mutating func parse(precedence: Precedence) -> any Expr {
		checkForInfiniteLoop()

		var lhs: (any Expr)?
		let rule = current.kind.rule

		if let prefix = rule.prefix {
			lhs = prefix(&self, precedence.canAssign)
		}

		while precedence < current.kind.rule.precedence {
			if let infix = current.kind.rule.infix, lhs != nil {
				lhs = infix(&self, precedence.canAssign, lhs!)
				skip(.newline)
			}
		}

		return lhs ?? ErrorSyntax(
			token: current,
			expected: .type(ExprStmtSyntax.self)
		)
	}

	private mutating func parameterList() -> ParameterListSyntax {
		if match(.rightParen) {
			return ParameterListSyntax(
				position: previous.start,
				length: 0,
				parameters: []
			)
		}

		let start = current.start
		var parameters: [IdentifierSyntax] = []

		repeat {
			guard let identifier = consume(IdentifierSyntax.self) else {
				break
			}

			parameters.append(identifier)
		} while match(.comma)

		consume(.rightParen, "Expected ')' after parameter list")
		return ParameterListSyntax(
			position: start,
			length: current.start - start,
			parameters: parameters
		)
	}

	private mutating func block() -> BlockStmtSyntax {
		skip(.newline) // for brace on next line style that i don't love

		let start = current.start
		consume(.leftBrace, "Expected '{' before function body")

		var decls: [any Decl] = []

		while !check(.rightBrace), !check(.eof) {
			skip(.newline)
			decls.append(decl())
			skip(.newline)
		}

		consume(.rightBrace, "Expected '{' after function body")

		return BlockStmtSyntax(
			position: start,
			length: current.start - start,
			decls: decls
		)
	}

	mutating func argumentList(terminator: Token.Kind) -> ArgumentListSyntax {
		let start = current.start
		var arguments: [any Expr] = []

		if !match(terminator) {
			repeat {
				arguments.append(parse(precedence: .assignment))
			} while match(.comma) && !match(.eof)

			consume(terminator, "Expected ')' after argument list")
		}

		return ArgumentListSyntax(
			position: start,
			length: current.start - start,
			arguments: arguments
		)
	}
}
