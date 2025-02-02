//
//  Compiler+Statements.swift
//
//
//  Created by Pat Nakajima on 7/5/24.
//

extension Compiler {
	func statement() {
		parser.skip(.statementTerminators)

		if parser.match(.return) {
			returnStatement()
		} else if parser.match(.print) {
			printStatement()
		} else if parser.match(.if) {
			ifStatement()
		} else if parser.match(.while) {
			whileStatement()
		} else if parser.match(.leftBrace) {
			beginScope()
			block()
			endScope()
		} else {
			expressionStatement()
		}

		parser.skip(.statementTerminators)
	}

	func expressionStatement() {
		expression()
		parser.consume(.statementTerminators, "Expected ';' after expression")
		emit(opcode: .pop)
	}

	func printStatement() {
		expression()
		parser.consume(.statementTerminators, "Expected ';' after value.")
		emit(opcode: .print)
	}

	func returnStatement() {
		if function.kind == .main {
			error("Cannot return from top level", at: parser.previous)
			return
		}

		if function.kind == .initializer {
			error("Cannot return from init", at: parser.previous)
			return
		}

		if parser.match(.statementTerminators) {
			emitReturn()
		} else {
			expression()
			parser.consume(.statementTerminators, "Expected ';' after return value")
			emit(opcode: .return)
		}
	}

	func ifStatement() {
		expression() // Add the if EXPRESSION to the stack

		let thenJumpLocation = emit(jump: .jumpIfFalse)
		emit(opcode: .pop) // Pop the condition off the stack

		parser.consume(.leftBrace, "Expected '{' before `if` statement.")
		block()

		let elseJump = emit(jump: .jump)

		// Backpack the jump
		patchJump(thenJumpLocation)
		emit(opcode: .pop) // Pop the condition off the stack

		if parser.match(.else) {
			statement()
		}

		patchJump(elseJump)
	}

	func whileStatement() {
		// This is where we return to while the condition is true
		let loopStart = chunk.count

		// Add the condition to the top of the stack
		expression()

		// Get the while condition
		parser.consume(.leftBrace, "Expected '{' after while condition")

		// Get the instruction to leave the loop
		let exitJump = emit(jump: .jumpIfFalse)
		emit(opcode: .pop) // Clean up the stack

		// The body of the loop
		block()
		emit(loop: loopStart)

		patchJump(exitJump)
		emit(opcode: .pop)
	}
}
