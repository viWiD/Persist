#!/bin/bash

set -e # exit on failure

# Run Tests via iOS
xcodebuild test -workspace Persist.xcworkspace -scheme Persist-iOS -destination "platform=iOS Simulator,name=iPhone 6s,OS=9.3"
