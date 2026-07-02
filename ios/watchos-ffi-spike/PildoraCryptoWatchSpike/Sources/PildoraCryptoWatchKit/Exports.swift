// Exports.swift — module anchor for PildoraCryptoWatchKit.
//
// This library target wraps the UniFFI-generated Swift bindings so the package
// exposes a buildable library *product* with an explicit watchOS platform.
// Without a library product, `xcodebuild` cannot infer a run destination for the
// test scheme ("Supported platforms for the buildables ... is empty").
//
// The generated bindings file (pildora_crypto_ffi.swift) is copied into this
// directory by ../../run-watchos-tests.sh and compiled alongside this file. Its
// public free functions (deriveMasterKey, itemEncrypt, ...) are re-exported as
// part of the PildoraCryptoWatchKit module and imported by the test target.

@_exported import Foundation
