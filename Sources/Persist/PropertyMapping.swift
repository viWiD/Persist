//
//  PropertyMapping.swift
//  Pods
//
//  Created by Nils Fischer on 01.04.16.
//
//

import Foundation

public struct PropertyMapping: CustomDebugStringConvertible {
    
    let name: String
    let key: String
    let transformer: Transformer?
    
    public var debugDescription: String {
        return "\(name) <-> \(key)"
    }
    
}

public func map(propertyNamed propertyName: String, toKey key: String, transformer: Transformer? = nil) -> PropertyMapping {
    return PropertyMapping(name: propertyName, key: key, transformer: transformer)
}
public func map(key key: String, toPropertyNamed propertyName: String, transformer: Transformer? = nil) -> PropertyMapping {
    return PropertyMapping(name: propertyName, key: key, transformer: transformer)
}

// TODO: provide shortcut for snake_case mapping

extension PropertyMapping: StringLiteralConvertible {
    
    public init(stringLiteral value: StringLiteralType) {
        self.init(name: value, key: value, transformer: nil)
    }
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        self.init(name: value, key: value, transformer: nil)
    }
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        self.init(name: value, key: value, transformer: nil)
    }
    
}

extension PropertyMapping: Hashable, Equatable {
    
    public var hashValue: Int {
        return name.hashValue // TODO: is this enough?
    }
    
}

public func ==(lhs: PropertyMapping, rhs: PropertyMapping) -> Bool {
    return lhs.name == rhs.name && lhs.key == rhs.key
}

