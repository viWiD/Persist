//
//  TransformerTests.swift
//  Persist
//
//  Created by Nils Fischer on 13.04.16.
//  Copyright © 2016 viWiD Webdesign & iOS Development. All rights reserved.
//

import XCTest
import Freddy
import CoreData
@testable import Persist

class CustomTransformer: Transformer {
    public override func transformedValue(value: AnyObject?) -> AnyObject? {
        return "custom"
    }
}

class TransformerTests: XCTestCase {
    

    func testTransformationFromString() {
        XCTAssertEqual(try JSON.String("value").transformedTo(.StringAttributeType) as? String, "value")
        XCTAssertEqual(try JSON.String("2013-10-22T15:15:00Z").transformedTo(.DateAttributeType) as? NSDate, NSDate(timeIntervalSince1970: 1382454900))
        XCTAssertEqual(try JSON.String("http://www.viwid.com/").transformedTo(.TransformableAttributeType) as? NSURL, NSURL(string: "http://www.viwid.com/")!)
    }
    
    func testCustomTransformerIsUsed() {
        XCTAssertEqual(try JSON.String("value").transformedTo(.StringAttributeType, transformer: CustomTransformer()) as? String, "custom")
    }
    
    
    // MARK: - Transformers
    
    func testIdentityTransformer() {
        let identityTransformer = IdentityTransformer()
        XCTAssertEqual(identityTransformer.transformedValue("value") as? String, "value", "Identity transformer does not transform string to itself.")
    }
    
    func testFormattedNumberTransformer() {
        let numberFormatter = NSNumberFormatter()
        numberFormatter.allowsFloats = false
        let transformer = FormattedNumberTransformer(numberFormatter: numberFormatter)
        XCTAssertEqual(transformer.transformedValue("1") as? NSNumber, 1, "Formatted number transformer does not transform valid string to number.")
        let v1 = transformer.transformedValue("1.5") // TODO: why can't this go directly in assert?
        XCTAssertNil(v1, "Formatted number transformer transforms invalid string.")
        let v2 = transformer.transformedValue(1)
        XCTAssertNil(v2, "Formatted number transformer should only accept strings.")
    }
    
    func testNumberFormatTransformer() {
        let numberFormatter = NSNumberFormatter()
        numberFormatter.allowsFloats = false
        let transformer = NumberFormatTransformer(numberFormatter: numberFormatter)
        XCTAssertEqual(transformer.transformedValue(1) as? String, "1", "Number format transformer does not transform valid number to string.")
        // TODO: what behaviour do we want?
//        let v1 = transformer.transformedValue(1.5)
//        XCTAssertNil(v1, "Number format transformer transforms invalid number.")
        let v2 = transformer.transformedValue("1")
        XCTAssertNil(v2, "Number format transformer should only accept numbers.")
    }
    
    func testISO8601DateTransformer() {
        let transformer = ISO8601DateTransformer()
        XCTAssertEqual(transformer.transformedValue("2013-10-22T15:15:00Z") as? NSDate, NSDate(timeIntervalSince1970: 1382454900), "ISO8601DateTransformer does not transform valid string to correct date.")
        let v1 = transformer.transformedValue("2013-10-22")
        XCTAssertNil(v1, "ISO8601DateTransformer transforms invalid string.")
        let v2 = transformer.transformedValue(1)
        XCTAssertNil(v2, "ISO8601DateTransformer should only accept strings.")
    }
    
}
