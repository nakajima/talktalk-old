///  UnaryExprSyntax.swift
//
//
//  Created by Pat Nakajima on 7/8/24.
//
public struct UnaryExprSyntax: Syntax, Expr {
	public let position: Int
	public let length: Int

	public let op: UnaryOperator
	public let rhs: any Expr

	public func accept<Visitor: ASTVisitor>(_ visitor: inout Visitor) -> Visitor.Value {
		visitor.visit(self)
	}
}
