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
    
    init(key: String, name: String) {
        self.name = name
        self.key = key
    }
    
    public var debugDescription: String {
        return "\(name) <-> \(key)"
    }
    
}

public func map(propertyNamed propertyName: String, toKey key: String) -> PropertyMapping {
    return PropertyMapping(key: key, name: propertyName)
}
public func map(key key: String, toPropertyNamed propertyName: String) -> PropertyMapping {
    return PropertyMapping(key: key, name: propertyName)
}

// TODO: provide shortcut for snake_case mapping

extension PropertyMapping: StringLiteralConvertible {
    
    public init(stringLiteral value: StringLiteralType) {
        self.init(key: value, name: value)
    }
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        self.init(key: value, name: value)
    }
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        self.init(key: value, name: value)
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

