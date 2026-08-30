# Upgrading from 1.x

Version 2 is a breaking rebuild with no automatic data migration.

- Existing GitHub issues are not imported. Export anything you need before upgrading.
- The GitHub API surface is removed: `GitHubService`, `GitHubCredentials`, `GitHubIssue`,
  `VotingService`, `IssueOwnershipService`, `IssuesListView` and `CompletedIssuesView`.
- `DeviceInfo.generateReport()` is replaced by structured `DeviceInfo.current()`.
- `getDeviceID()` and `getIOSVersion()` are removed.
- Local vote and ownership state in UserDefaults is removed; CloudKit is authoritative.
- Voting can be withdrawn, following is separate from voting, reports have categories, requests can
  contain three images, and completed requests record the version containing the fix.

Before updating:

1. Tag and preserve the final 1.x release.
2. Export any GitHub issues you want to retain.
3. Revoke the GitHub personal access token used by 1.x. Removing it from new source does not remove it
   from already-distributed builds.
4. Complete the CloudKit setup in the README.
5. Test the migration as a new installation; there is no shared backend state with 1.x.

SPM clients pinned to a 1.x version do not move to 2.x automatically.
