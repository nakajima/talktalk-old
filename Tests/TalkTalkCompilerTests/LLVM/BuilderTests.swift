//
//  BuilderTests.swift
//
//
//  Created by Pat Nakajima on 7/16/24.
//
import C_LLVM
@testable import TalkTalkCompiler
import Testing

struct BuilderTests {
	@Test("basics") func basics() throws {
		let module = LLVM.Module(name: "basic", in: .global)
		let builder = LLVM.Builder(module: module)

		let mainType = LLVM.FunctionType(context: .global, returning: .void(.global), parameters: [], isVarArg: false)
		let function = builder.addFunction(named: "main", mainType)!

		let int8 = LLVM.IntType(width: 8, context: .global)
		let printfType = LLVM.FunctionType(
			context: .global,
			returning: LLVM.IntType(width: 32, context: .global),
			parameters: [*int8],
			isVarArg: true
		)
		_ = builder.addFunction(named: "printf", printfType)

		LLVMAppendBasicBlockInContext(module.context.ref, function.ref, "entry")
	}
}
