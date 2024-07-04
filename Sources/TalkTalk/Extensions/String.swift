//
//  String.swift
//
//
//  Created by Pat Nakajima on 7/1/24.
//
extension String {
	func index(at offset: Int) -> String.Index {
		index(startIndex, offsetBy: offset)
	}

	subscript(_ offset: Int) -> Character {
		self[index(startIndex, offsetBy: offset)]
	}

	subscript(_ range: Range<Int>) -> Substring {
		self[index(at: range.lowerBound) ..< index(at: range.upperBound)]
	}
}

#if canImport(Glibc)
import Glibc

extension String {
	init(format: String, _ arguments: CVarArg...) {
		let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 1024)
		defer {
			buffer.deallocate()
		}
		withVaList(arguments) { pointer in
			vsnprintf(buffer, 1024, format, pointer)
		}
		self = String(cString: buffer)
	}
}

#elseif canImport(Foundation)
import Foundation
#endif
