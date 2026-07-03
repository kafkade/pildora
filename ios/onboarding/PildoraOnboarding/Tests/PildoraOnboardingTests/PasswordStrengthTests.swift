import XCTest
@testable import PildoraOnboarding

final class PasswordStrengthTests: XCTestCase {

    func testEmptyPasswordIsBaseline() {
        let result = PasswordStrengthEvaluator.evaluate("")
        XCTAssertEqual(result, .empty)
        XCTAssertEqual(result.level, .veryWeak)
    }

    func testCommonPasswordCollapsesToVeryWeak() {
        let result = PasswordStrengthEvaluator.evaluate("password")
        XCTAssertEqual(result.level, .veryWeak)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testEmbeddedCommonWordIsPenalized() {
        let strong = PasswordStrengthEvaluator.evaluate("Tr!buneXutopia92")
        let weakened = PasswordStrengthEvaluator.evaluate("password!Xutopia92")
        XCTAssertLessThan(weakened.entropyBits, strong.entropyBits)
        XCTAssertTrue(weakened.warnings.contains { $0.lowercased().contains("common") })
    }

    func testSequentialRunIsPenalized() {
        let result = PasswordStrengthEvaluator.evaluate("abcd1234")
        XCTAssertTrue(result.warnings.contains { $0.lowercased().contains("sequence") })
    }

    func testRepeatedCharactersArePenalized() {
        let result = PasswordStrengthEvaluator.evaluate("aaaaaaaa")
        XCTAssertTrue(result.warnings.contains { $0.lowercased().contains("repeat") })
        XCTAssertEqual(result.level, .veryWeak)
    }

    func testLongMixedPassphraseIsStrong() {
        let result = PasswordStrengthEvaluator.evaluate("Xk9!vBw2#qLmZ7$r")
        XCTAssertGreaterThanOrEqual(result.level, .strong)
    }

    func testLongerPasswordScoresHigher() {
        let short = PasswordStrengthEvaluator.evaluate("Xk9!vB")
        let long = PasswordStrengthEvaluator.evaluate("Xk9!vBXk9!vBXk9!vB")
        XCTAssertGreaterThan(long.entropyBits, short.entropyBits)
    }

    func testEntropyBucketBoundaries() {
        XCTAssertEqual(PasswordStrengthEvaluator.level(forEntropy: 10), .veryWeak)
        XCTAssertEqual(PasswordStrengthEvaluator.level(forEntropy: 30), .weak)
        XCTAssertEqual(PasswordStrengthEvaluator.level(forEntropy: 50), .fair)
        XCTAssertEqual(PasswordStrengthEvaluator.level(forEntropy: 70), .strong)
        XCTAssertEqual(PasswordStrengthEvaluator.level(forEntropy: 100), .veryStrong)
    }

    // MARK: Policy

    func testPolicyRejectsShortPassword() {
        let policy = PasswordPolicy.standard
        let pw = "Ab1!"
        let strength = PasswordStrengthEvaluator.evaluate(pw)
        XCTAssertFalse(policy.isAcceptable(password: pw, confirmation: pw, strength: strength))
        let lengthReq = policy.requirements(password: pw, confirmation: pw, strength: strength)
            .first { $0.id == .minLength }
        XCTAssertEqual(lengthReq?.isSatisfied, false)
    }

    func testPolicyRequiresMatchingConfirmation() {
        let policy = PasswordPolicy.standard
        let pw = "Xk9!vBw2#qLmZ7$r"
        let strength = PasswordStrengthEvaluator.evaluate(pw)
        XCTAssertFalse(policy.isAcceptable(password: pw, confirmation: "different", strength: strength))
        XCTAssertTrue(policy.isAcceptable(password: pw, confirmation: pw, strength: strength))
    }

    func testPolicyOmitsMatchRequirementWhenConfirmationNil() {
        let policy = PasswordPolicy.standard
        let pw = "Xk9!vBw2#qLmZ7$r"
        let strength = PasswordStrengthEvaluator.evaluate(pw)
        let reqs = policy.requirements(password: pw, confirmation: nil, strength: strength)
        XCTAssertFalse(reqs.contains { $0.id == .matchesConfirmation })
    }
}
