#!/usr/bin/env swift

import Carbon
import Foundation

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let property = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
}

func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let property = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    let value = Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue()
    return CFBooleanGetValue(value)
}

func urlProperty(_ source: TISInputSource, _ key: CFString) -> URL? {
    guard let property = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFURL>.fromOpaque(property).takeUnretainedValue() as URL
}

let expectedBundleID = CommandLine.arguments.dropFirst().first
    ?? "com.shendongchun.inputmethod.windwhisper"
let includeAllInstalled = CommandLine.arguments.dropFirst(2).first != "enabled-only"
let filter = [kTISPropertyBundleID as String: expectedBundleID] as CFDictionary
guard let result = TISCreateInputSourceList(filter, includeAllInstalled) else {
    print("sourceCount=0")
    exit(0)
}
let sources = result.takeRetainedValue() as! [TISInputSource]
print("sourceCount=\(sources.count)")
for source in sources {
    let identifier = stringProperty(source, kTISPropertyInputSourceID) ?? "<missing>"
    let bundleIdentifier = stringProperty(source, kTISPropertyBundleID) ?? "<missing>"
    let category = stringProperty(source, kTISPropertyInputSourceCategory) ?? "<missing>"
    let type = stringProperty(source, kTISPropertyInputSourceType) ?? "<missing>"
    print("id=\(identifier)")
    print("bundle=\(bundleIdentifier)")
    print("category=\(category)")
    print("type=\(type)")
    print("enabled=\(boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false)")
    print("selected=\(boolProperty(source, kTISPropertyInputSourceIsSelected) ?? false)")
    print("selectCapable=\(boolProperty(source, kTISPropertyInputSourceIsSelectCapable) ?? false)")
    print("iconURL=\(urlProperty(source, kTISPropertyIconImageURL)?.path ?? "<missing>")")
    print("---")
}
