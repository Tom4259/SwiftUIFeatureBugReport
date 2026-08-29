//
//  RecordIDTests.swift
//  SwiftUIFeatureBugReportTests
//

import Testing

@testable import SwiftUIFeatureBugReport

/// `RecordID` is the only thing enforcing one-vote-per-user: CloudKit has no unique constraints, so
/// uniqueness comes from composing a name that a second save collides with. A change to any of these
/// strings is silent - nothing fails to build, nothing throws, votes simply stop being unique - so
/// these tests pin the exact output rather than merely asserting a shape.
@Suite("Deterministic record names")
struct RecordIDTests {

    @Test("Vote, report and follow names are composed from the request and the user")
    func composedNames() {

        #expect(RecordID.vote(request: "req1", user: "_user1") == "vote_req1__user1")
        #expect(RecordID.report(request: "req1", user: "_user1") == "report_req1__user1")
        #expect(RecordID.follow(request: "req1", user: "_user1") == "follow_req1__user1")
        #expect(RecordID.metadata(request: "req1") == "meta_req1")
    }

    @Test("The same request and user always collide; different users never do")
    func uniquenessMechanism() {

        #expect(RecordID.vote(request: "req1", user: "_a") == RecordID.vote(request: "req1", user: "_a"))
        #expect(RecordID.vote(request: "req1", user: "_a") != RecordID.vote(request: "req1", user: "_b"))
        #expect(RecordID.vote(request: "req1", user: "_a") != RecordID.vote(request: "req2", user: "_a"))
    }

    /// The hash behind an activity name is hand-rolled FNV-1a precisely because `hashValue` is seeded
    /// per process. If it ever regresses to a seeded hash these expectations change on the next run,
    /// which is the only way that failure ever becomes visible - in production it would just mean
    /// every duplicate-suppressed announcement quietly sending a second push.
    @Test("Activity names are stable across processes")
    func activityNameIsPinned() {

        #expect(RecordID.activity(request: "req1",
                                  kind: "shipped",
                                  recipient: "_user1",
                                  message: "Fixed in 2.1") == "activity_req1_shipped_811652b3__user1")
    }

    @Test("A different message is a different announcement, an identical one is not")
    func activityNameVariesWithMessageOnly() {

        let first = RecordID.activity(request: "r", kind: "shipped", recipient: "_u", message: "Fixed in 2.1")
        let same = RecordID.activity(request: "r", kind: "shipped", recipient: "_u", message: "Fixed in 2.1")
        let other = RecordID.activity(request: "r", kind: "shipped", recipient: "_u", message: "Fixed in 2.2")

        #expect(first == same)
        #expect(first != other)
    }

    @Test("Composed names stay inside CloudKit's character set")
    func namesUseOnlyLegalCharacters() {

        let legal = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

        let names = [
            RecordID.vote(request: "req-1.a", user: "_user1"),
            RecordID.report(request: "req-1.a", user: "_user1"),
            RecordID.follow(request: "req-1.a", user: "_user1"),
            RecordID.metadata(request: "req-1.a"),
            RecordID.activity(request: "req-1.a", kind: "shipped", recipient: "_user1", message: "Done ✅")
        ]

        for name in names {

            #expect(name.allSatisfy { legal.contains($0) }, "\(name) contains an illegal character")
            #expect(name.count <= 255)
        }
    }
}
