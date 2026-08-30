# Schema and permissions

The repository ships two complete schemas:

- `Schema.ckdb` includes user `Comment` records.
- `Schema-NoComments.ckdb` omits `Comment` but keeps developer `DevComment` records.

Use a checked-in variant instead of editing a schema during installation. When changing the package's
schema itself, work in Development, export the result, review the diff, and update both variants.

## Record types

| Record type | Purpose |
|---|---|
| `Request` | Public bug or feature request and optional images |
| `Vote` | One deterministic vote per user and request |
| `Report` | One categorized report per user and request |
| `Comment` | Optional user reply |
| `DevComment` | Developer-authenticated reply |
| `Activity` | User update feed and push trigger |
| `Follow` | Private subscription to a request |
| `RequestMetadata` | Private prefilling metadata |

`Users` is CloudKit's built-in user type. Its queryable record ID is needed to configure the
`dev` role.

## Required indexes

Every included custom record type needs a queryable `___recordID`.

| Record type | Additional indexes |
|---|---|
| `Request` | `title` queryable/searchable; `type`, `status`, `moderation`, `imageState`, `labels`, `resolvedInVersion`, `creatorID`, device fields queryable; `lastActivityAt` and creation time sortable |
| `Vote` | `request` queryable; creation time sortable |
| `Report` | `request` and `category` queryable |
| `Follow` | `request` queryable; creation time sortable |
| `Comment`, `DevComment` | `request`, `requestCreator`, `creatorID` queryable |
| `Activity` | `request`, `recipientID`, `kind` queryable; creation time sortable |
| `RequestMetadata` | `request` queryable |
| `Users` | `___recordID` queryable |

`title` is intentionally the only searchable `Request` field. Search-before-submit uses
`self CONTAINS`; marking `body` searchable silently widens that query without adding relevance
ranking.

## Permission invariants

- `RequestMetadata` allows authenticated creation but not world reading.
- `DevComment` grants creation only to `dev`, making developer authorship unspoofable.
- `Comment` and `Follow` grant developer writes so account deletion can remove another user's data.
- `Vote`, `Report` and `Follow` grant their creator writes so votes can be withdrawn, follows
  cancelled and reports deleted.
- `Report` contains a category but no free-text detail because reports are world-readable for
  client-side threshold counting.
- `Request.images` is a `LIST<ASSET>`.
- `resolvedInVersion` is separate from the version from which a request was reported.

If user comments are disabled, use `Schema-NoComments.ckdb` and set `allowComments: false`. The
configuration flag controls the client; omitting the record type enforces the decision at CloudKit.
