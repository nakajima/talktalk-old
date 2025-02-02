//
//  UnaryOperator.swift
//
//
//  Created by Pat Nakajima on 7/8/24.
//
public struct UnaryOperator: Syntax {
	public enum Kind {
		case minus, bang
	}

	public let position: Int
	public let length: Int
	public let kind: Kind

	public var description: String {
		switch kind {
		case .minus:
			"-"
		case .bang:
			"!"
		}
	}

	public func accept<Visitor: ASTVisitor>(_ visitor: inout Visitor) -> Visitor.Value {
		visitor.visit(self)
	}
}
