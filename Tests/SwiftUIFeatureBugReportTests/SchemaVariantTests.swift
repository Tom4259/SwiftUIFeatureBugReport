//
//  SchemaVariantTests.swift
//  SwiftUIFeatureBugReportTests
//

import Foundation
import Testing

@Suite("Checked-in CloudKit schemas")
struct SchemaVariantTests {

    private func schema(named name: String) throws -> String {

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(contentsOf: repositoryRoot.appendingPathComponent(name), encoding: .utf8)
    }

    @Test("Both variants define every required shared record type")
    func sharedTypes() throws {

        let schemas = try [schema(named: "Schema.ckdb"), schema(named: "Schema-NoComments.ckdb")]
        let required = ["Activity", "DevComment", "Follow", "Report", "Request",
                        "RequestMetadata", "Users", "Vote"]

        for contents in schemas {

            for recordType in required {

                #expect(contents.contains("RECORD TYPE \(recordType) ("))
            }

            #expect(contents.contains("CREATE ROLE dev;"))
        }
    }

    @Test("Only the comments-enabled schema defines Comment")
    func commentVariant() throws {

        let comments = try schema(named: "Schema.ckdb")
        let noComments = try schema(named: "Schema-NoComments.ckdb")

        #expect(comments.contains("RECORD TYPE Comment ("))
        #expect(!noComments.contains("RECORD TYPE Comment ("))
    }
}
