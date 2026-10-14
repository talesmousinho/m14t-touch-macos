import Foundation

var failures = 0
var checks = 0
runGestureReplayChecks { condition, message in
    checks += 1
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}
print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
