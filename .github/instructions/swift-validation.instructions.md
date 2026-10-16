---
description: "Use when modifying this Swift package, Swift source files, Package.swift, tests, or install/autostart behavior. Covers required build and test validation."
applyTo: "Package.swift, Sources/**/*.swift, Tests/**/*.swift, install.sh"
---
# Swift Package Validation

- After changing Swift source, package manifest, tests, or install/autostart behavior, run `swift build -c release`.
- Run `swift test` after code or test changes; the expected suite is XCTest-based and currently has 14 tests.
- Treat the Swift Testing summary `0 tests in 0 suites` as non-blocking when the preceding XCTest suite reports all tests passed.
- If validation fails because of local developer tools, record the exact command, failure, selected developer directory, and any successful narrower checks.
- Keep fixes focused on the touched behavior; do not refactor unrelated driver, calibration, or README content just to satisfy validation.
