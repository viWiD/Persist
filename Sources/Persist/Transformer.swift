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


public enum TransformationError: ErrorType, CustomDebugStringConvertible {
    case NoTransformerFound(value: JSON, attributeType: NSAttributeType)
    public var debugDescription: String {
        switch self {
        case .NoTransformerFound(value: let value, attributeType: let attributeType): return "No transformer found to transform \(value) to \(attributeType)."
        }
    }
}


extension JSON {
    
    internal func transformedTo(attributeType: NSAttributeType, transformer: Transformer? = nil) throws -> PrimitiveValue? {
        
        // use the given transformer, if available
        if let transformer = transformer {
            return transformer.transformedValue(self.primitiveValue) as? PrimitiveValue // TODO: reconsider this cast, make PrimitiveValue = AnyObject?
        }
        
        // try to find a default transformer
        if let transformer = self.defaultTransformerForAttributeType(attributeType) {
            return transformer.transformedValue(self.primitiveValue) as? PrimitiveValue // TODO: reconsider this cast, make PrimitiveValue = AnyObject?
        }
        
        if case .Null = self {
            return nil // TODO: make sure to give appropriate error if the transformed value is nil but the attribute is non-optional
        }
        
        throw TransformationError.NoTransformerFound(value: self, attributeType: attributeType)
    }
    
    // TODO: don't instantiate the transformers every time
    private func defaultTransformerForAttributeType(attributeType: NSAttributeType) -> Transformer? {
        switch attributeType {
        case .StringAttributeType:
            switch self {
            case .String: return IdentityTransformer()
            case .Int, .Double, Bool:
                let numberFormatter = NSNumberFormatter()
                return NumberFormatTransformer(numberFormatter: numberFormatter)
            default: return nil
            }
        case .DateAttributeType:
            switch self {
            case .String(let stringValue): return ISO8601DateTransform() // TODO: fallback to others
            default: return nil
            }
        case .BooleanAttributeType:
            switch self {
            case .Bool: return IdentityTransformer()
            case .Int(let integerValue): return [ 0, 1 ].contains(integerValue) ? IdentityTransformer() : nil
            case .Double(let doubleValue): return [ 0, 1 ].contains(doubleValue) ? IdentityTransformer() : nil
            // TODO: interpret strings
            default: return nil
            }
        case .Integer16AttributeType, .Integer32AttributeType, .Integer64AttributeType, .FloatAttributeType, .DoubleAttributeType:
            switch self {
            case .Int, .Double, .Bool: return IdentityTransformer()
            case .String:
                let numberFormatter = NSNumberFormatter()
                return FormattedNumberTransformer(numberFormatter: numberFormatter)
            default: return nil
            }
        case .DecimalAttributeType:
            return nil // TODO
        case .ObjectIDAttributeType:
            return nil // TODO
        case .UndefinedAttributeType:
            return nil // TODO
        case .BinaryDataAttributeType:
            return nil // TODO
        case .TransformableAttributeType:
            switch self {
            case .String: return URLTransformer() // TODO: don't always interpret as URL?
            default: return nil // TODO
            }
        }
    }
    
    private var primitiveValue: PrimitiveValue? {
        switch self {
        case .Bool(let boolValue): return boolValue
        case .Int(let intValue): return intValue
        case .Double(let doubleValue): return doubleValue
        case .String(let stringValue): return stringValue
        case .Null: return nil
        case .Array(let arrayValue): return NSArray(array: arrayValue.map({ $0.primitiveValue ?? NSNull() }))
        case .Dictionary(let dictionaryValue): return NSDictionary(dictionary: dictionaryValue.reduce([:]) { objectDictionary, row in
                var objectDictionary = objectDictionary
                objectDictionary[row.0] = row.1.primitiveValue ?? NSNull()
                return objectDictionary
            })
        }
    }
    
}


// MARK: - Transformers

public typealias Transformer = NSValueTransformer


public class IdentityTransformer: Transformer {
    
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        return value
    }
    
}


public class URLTransformer: Transformer {
    
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        guard let urlString = value as? String else {
            return nil
        }
        return NSURL(string: urlString)
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return false
    }
    
    public override class func transformedValueClass() -> AnyClass {
        return NSURL.self
    }
    
}


public class FormattedNumberTransformer: Transformer {
    
    let numberFormatter: NSNumberFormatter
    
    public init(numberFormatter: NSNumberFormatter) {
        self.numberFormatter = numberFormatter
    }
    
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        guard let formattedNumber = value as? String else {
            return nil
        }
        return numberFormatter.numberFromString(formattedNumber)
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return false
    }
    
    public override class func transformedValueClass() -> AnyClass {
        return NSNumber.self
    }
    
}


public class NumberFormatTransformer: Transformer { // TODO: rename
    
    let numberFormatter: NSNumberFormatter
    
    public init(numberFormatter: NSNumberFormatter) {
        self.numberFormatter = numberFormatter
    }
    
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        guard let number = value as? NSNumber else {
            return nil
        }
        return numberFormatter.stringFromNumber(number)
    }
   
    public override class func allowsReverseTransformation() -> Bool {
        return false
    }
    
    public override class func transformedValueClass() -> AnyClass {
        return NSString.self
    }
    
}


public class FormattedDateTransformer: Transformer {
    
    public let dateFormatter: NSDateFormatter
    
    public init(dateFormatter: NSDateFormatter) {
        self.dateFormatter = dateFormatter
    }
    
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        guard let formattedDate = value as? String else {
            return nil
        }
        return dateFormatter.dateFromString(formattedDate)
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return false
    }
    
    public override class func transformedValueClass() -> AnyClass {
        return NSDate.self
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
