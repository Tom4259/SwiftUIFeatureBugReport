//
//  VoteTallyTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

/// Tallies count distinct voters, so extra `Vote` records saved by one account cannot inflate a count.
@Suite("Vote tallies")
struct VoteTallyTests {

    private let requestA = CKRecord.ID(recordName: "request-a")
    private let requestB = CKRecord.ID(recordName: "request-b")

    @Test("Several votes from one account on one request count once")
    func duplicatesCountOnce() {

        let entries = [
            VoteService.VoteEntry(request: requestA, voter: "alice"),
            VoteService.VoteEntry(request: requestA, voter: "alice"),
            VoteService.VoteEntry(request: requestA, voter: "alice")
        ]

        #expect(VoteService.distinctTallies(entries)[requestA] == 1)
    }

    @Test("Distinct voters and distinct requests are counted independently")
    func distinctVotersAndRequests() {

        let entries = [
            VoteService.VoteEntry(request: requestA, voter: "alice"),
            VoteService.VoteEntry(request: requestA, voter: "bob"),
            VoteService.VoteEntry(request: requestB, voter: "alice")
        ]

        let tallies = VoteService.distinctTallies(entries)

        #expect(tallies[requestA] == 2)
        #expect(tallies[requestB] == 1)
    }

    @Test("No votes means no tallies")
    func empty() {

        #expect(VoteService.distinctTallies([]).isEmpty)
    }
}

/// What a `Vote` record contributes to the tally, read straight off the record.
@Suite("Vote entries")
struct VoteEntryTests {

    private let request = CKRecord.ID(recordName: "request-a")

    private func vote(named name: String, on request: CKRecord.ID?) -> CKRecord {

        let record = CKRecord(recordType: RecordType.vote, recordID: CKRecord.ID(recordName: name))

        if let request { record[FieldKey.request] = CKRecord.Reference(recordID: request, action: .none) }

        return record
    }

    @Test("A vote with no request reference contributes nothing")
    func noReference() {

        #expect(VoteService.VoteEntry(record: vote(named: "v1", on: nil)) == nil)
    }

    /// A record built locally has no creator, which is exactly the case CloudKit sometimes returns.
    @Test("Without a creator the vote's own record name stands in as the voter")
    func anonymousFallsBackToRecordName() throws {

        let entry = try #require(VoteService.VoteEntry(record: vote(named: "v1", on: request)))

        #expect(entry.request == request)
        #expect(entry.voter == "v1")
    }

    @Test("Anonymous votes count once each; the same record seen twice counts once")
    func anonymousTallies() {

        let entries = [vote(named: "v1", on: request),
                       vote(named: "v2", on: request),
                       vote(named: "v1", on: request)]
            .compactMap { VoteService.VoteEntry(record: $0) }

        #expect(VoteService.distinctTallies(entries)[request] == 2)
    }
}
