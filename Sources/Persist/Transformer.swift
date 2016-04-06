//
//  Transformer.swift
//  Pods
//
//  Created by Nils Fischer on 01.04.16.
//
//

import Foundation
import CoreData
import Freddy


internal extension JSON {
    
    enum TransformationError: ErrorType {
        case NotImplemented
    }
    
    func transformedTo(attributeType: NSAttributeType) throws -> NSObject? { // TODO: return descriptive typealias instead of NSObject
        switch attributeType {
        case .DateAttributeType:
            switch self {
            case .String(let stringValue):
                let transformer = ISO8601DateTransform() // TODO: fallback to others
                return try transformer.transform(stringValue)
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .BooleanAttributeType:
            switch self {
            case .Bool(let boolValue): return boolValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .StringAttributeType:
            switch self {
            case .String(let stringValue): return stringValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .Integer16AttributeType, .Integer32AttributeType, .Integer64AttributeType:
            switch self {
            case .Int(let intValue): return intValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .FloatAttributeType, .DoubleAttributeType:
            switch self {
            case .Int(let intValue): return intValue
            case .Double(let doubleValue): return doubleValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .TransformableAttributeType:
            switch self {
            case .String(let stringValue):
                let transformer = URLTransformer()
                return try transformer.transform(stringValue)
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        default:
            throw TransformationError.NotImplemented
        }
    }
    
    //    private var objectValue: NSObject {
    //        switch self {
    //        case .Bool(let boolValue): return boolValue
    //        case .Int(let intValue): return intValue
    //        case .Double(let doubleValue): return doubleValue
    //        case .String(let stringValue): return stringValue
    //        case .Null: return NSNull()
    //        case .Array(let arrayValue): return NSArray(array: arrayValue.map({ $0.objectValue }))
    //        case .Dictionary(let dictionaryValue): return NSDictionary(dictionary: dictionaryValue.reduce([:]) { objectDictionary, row in
    //                var objectDictionary = objectDictionary
    //                objectDictionary[row.0] = row.1.objectValue
    //                return objectDictionary
    //            })
    //        }
    //    }
}

public protocol Transformer {
    
    associatedtype FromType
    associatedtype ToType
    
    func transform(value: FromType) throws -> ToType
    
}

public class URLTransformer: Transformer {
    
    public typealias FromType = String
    public typealias ToType = NSURL?
    
    public enum URLTransformationError: ErrorType {
        case InvalidFormat(String)
    }
    
    public func transform(value: String) throws -> NSURL? {
        guard !value.isEmpty else {
            return nil
        }
        guard let url = NSURL(string: value) else {
            throw URLTransformationError.InvalidFormat(value)
        }
        return url
    }
    
}

public class FormattedDateTransformer: Transformer {
    
    public typealias FromType = String
    public typealias ToType = NSDate?
    
    public let dateFormatter: NSDateFormatter
    
    public init(dateFormatter: NSDateFormatter) {
        self.dateFormatter = dateFormatter
    }
    
    public enum FormattedDateTransformationError: ErrorType {
        case InvalidFormat(String)
    }
    
    public func transform(value: String) throws -> NSDate? {
        guard !value.isEmpty else {
            return nil
        }
        guard let result = dateFormatter.dateFromString(value) else {
            throw FormattedDateTransformationError.InvalidFormat(value)
        }
        return result
    }
    
}

public class ISO8601DateTransform: FormattedDateTransformer {
    
    public init() {
        let dateFormatter = NSDateFormatter()
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        super.init(dateFormatter: dateFormatter)
    }
    
}
