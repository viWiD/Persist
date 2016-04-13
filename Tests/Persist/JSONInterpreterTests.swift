//
//  JSONInterpreterTests.swift
//  Persist
//
//  Created by Nils Fischer on 13.04.16.
//  Copyright © 2016 viWiD Webdesign & iOS Development. All rights reserved.
//

import XCTest
import Freddy
@testable import Persist

class JSONInterpreterTests: XCTestCase {
    
    func testInterpretJSON() {
        XCTAssertEqual(try JSON.Int(1).map(identificationValueTransform: { String($0) }, propertyValuesTransform: { String($0) }), [ "1" ])
        XCTAssertEqual(try JSON.Array([ JSON.Int(1) ]).map(identificationValueTransform: { String($0) }, propertyValuesTransform: { String($0) }), [ "1" ])
        XCTAssertEqual(try JSON.Dictionary([ "value": JSON.Int(1) ]).map(identificationValueTransform: { String($0) }, propertyValuesTransform: { String($0["value"]!) }), [ "1" ])
    }
    
}
