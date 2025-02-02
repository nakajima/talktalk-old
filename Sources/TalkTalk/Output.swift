//
//  Output.swift
//
//
//  Created by Pat Nakajima on 7/2/24.
//

public protocol OutputCollector: AnyObject {
	func print(_ output: String, terminator: String)
	func debug(_ output: String, terminator: String)
}

public final class StdoutOutput: OutputCollector {
	var isDebug = false

	public func print(_ output: String, terminator: String) {
		Swift.print(output, terminator: terminator)
	}

	public func debug(_ output: String, terminator: String) {
		if isDebug {
			Swift.print(output, terminator: terminator)
		}
	}

	public init(isDebug: Bool = false) {
		self.isDebug = isDebug
	}
}

public extension OutputCollector {
	func print() {
		self.print("")
	}

	func debug() {
		debug("", terminator: "\n")
	}

	func debug(_ output: String) {
		debug(output, terminator: "\n")
	}

	func print(_ output: String) {
		self.print(output, terminator: "\n")
	}
}
