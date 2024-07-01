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
}
