# GitHub Feedback SDK for SwiftUI

A simple, lightweight SwiftUI package for collecting user feedback (bug reports and feature requests) directly in your iOS app using GitHub Issues as the backend.

## Features

✅ **Zero Dependencies** - Pure SwiftUI and GitHub API  
✅ **Anonymous Feedback** - No user accounts required  
✅ **Built-in Voting System** - Users can upvote feature requests  
✅ **Duplicate Prevention** - One vote per device per issue  
✅ **Device Info Collection** - Automatic device/app version reporting  
✅ **Clean UI Components** - Ready-to-use SwiftUI views  
✅ **Private Repository Support** - Keep feedback internal  
✅ **Real-time Updates** - Live vote counts and issue lists  


## Installation

### Swift Package Manager

1. In Xcode, go to **File** → **Add Package Dependencies**
2. Enter the repository URL:
```
https://github.com/yourusername/github-feedback-sdk
```
3. Click **Add Package**

## Quick Start

### 1. Create GitHub Repository & Token

1. **Create a repository** (can be private) for storing feedback
2. **Generate a Personal Access Token**:
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Create a **Fine-grained token** with these permissions for your repository:
     - **Issues**: Write
     - **Metadata**: Read
     - **Contents**: Read

### 2. Basic Setup

```swift
import SwiftUI

struct ContentView: View {
    // Configure your GitHub credentials
    private let gitHubCredentials = GitHubCredentials(
        owner: "your-username",      // Your GitHub username
        repo: "feedback-repo",       // Your repository name
        token: "github_pat_xxx..."   // Your GitHub token
    )
    
    private lazy var gitHubService = GitHubService(credentials: gitHubCredentials)
    
    var body: some View {
        NavigationStack {
            TabView {
                // Your main app
                YourMainView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                
                // Feedback system
                IssuesListView(gitHubService: gitHubService)
                    .tabItem {
                        Label("Feedback", systemImage: "exclamationmark.bubble")
                    }
            }
        }
    }
}
```

### 3. Standalone Feedback Form

```swift
struct SettingsView: View {
    @State private var showFeedback = false
    private let gitHubService = GitHubService(credentials: yourCredentials)
    
    var body: some View {
        List {
            Button("Send Feedback") {
                showFeedback = true
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackFormView(gitHubService: gitHubService)
        }
    }
}
```

## API Reference

### GitHubCredentials

```swift
public struct GitHubCredentials {
    public init(owner: String, repo: String, token: String)
}
```

**Parameters:**
- `owner`: Your GitHub username or organization
- `repo`: Repository name where issues will be created
- `token`: GitHub Personal Access Token

### GitHubService

```swift
@MainActor
public class GitHubService: ObservableObject {
    public var issues: [GitHubIssue] = []
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    public init(credentials: GitHubCredentials)
    public func loadIssues(type: IssueType = .all) async
    public func createIssue(title: String, description: String, type: IssueType, deviceInfo: String) async throws -> Int
    public func addVote(to issueNumber: Int) async throws
}
```

### VotingService

```swift
@MainActor
public class VotingService: ObservableObject {
    public func hasVoted(for issueNumber: Int) -> Bool
    public func addVote(to issueNumber: Int, using gitHubService: GitHubService) async throws
}
```

### SwiftUI Views

#### IssuesListView
Complete feedback interface with issue browsing, voting, and submission.

```swift
public struct IssuesListView: View {
    public init(gitHubService: GitHubService)
}
```

#### FeedbackFormView
Standalone form for submitting bug reports and feature requests.

```swift
public struct FeedbackFormView: View {
    public init(gitHubService: GitHubService)
}
```

## Issue Types

```swift
public enum IssueType: String, CaseIterable {
    case all = "All"
    case bugs = "Bugs" 
    case features = "Feature Requests"
}
```

## How It Works

1. **Issue Creation**: User feedback creates GitHub issues with automatic device info
2. **Voting System**: Vote counts are stored in issue descriptions as `👍 Votes: X`
3. **Local Tracking**: UserDefaults prevents duplicate votes per device
4. **Clean Display**: Device info and vote metadata are hidden from users
5. **Real-time Sync**: Issues and vote counts update automatically

## GitHub Issue Structure

Issues created by the SDK include:

```markdown
User's feedback description

---
**Device Information:**
Device: iPhone15,2  
iOS Version: 17.0
App Version: 1.0.0 (1)
Device ID: ABC-123-DEF

*Submitted via mobile app*

---
👍 Votes: 5
```

## Customization

### Custom Device Info

```swift
// Override device info collection
let customDeviceInfo = """
Device: \(DeviceInfo.getDeviceModel())
OS: \(DeviceInfo.getIOSVersion()) 
App: \(DeviceInfo.getAppVersion())
Custom Field: \(yourCustomData)
"""

try await gitHubService.createIssue(
    title: title,
    description: description, 
    type: .bugs,
    deviceInfo: customDeviceInfo
)
```

### Filtering Issues

```swift
// Load only feature requests
await gitHubService.loadIssues(type: .features)

// Load only bugs
await gitHubService.loadIssues(type: .bugs)

// Load all feedback
await gitHubService.loadIssues(type: .all)
```

## Error Handling

```swift
do {
    try await gitHubService.createIssue(...)
} catch GitHubError.failedToCreate {
    // Handle creation failure
} catch GitHubError.invalidResponse {
    // Handle API errors  
} catch VotingError.alreadyVoted {
    // Handle duplicate votes
}
```

## Security Best Practices

⚠️ **Important**: Never commit your GitHub token to version control

### Secure Token Storage

```swift
// Option 1: Environment variables
let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ""

// Option 2: Secrets file (add to .gitignore)
struct Secrets {
    static let githubToken = "your_token_here"
}

// Option 3: Property file
if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
   let plist = NSDictionary(contentsOfFile: path),
   let token = plist["GitHubToken"] as? String {
    // Use token
}
```

### .gitignore Example

```gitignore
# Secrets
Secrets.swift
Secrets.plist
Config.xcconfig

# GitHub token files
github-token.txt
credentials.json
```

## GitHub Repository Setup

### Recommended Labels

Create these labels in your GitHub repository for better organization:

- 🐛 `bug` (red) - For bug reports
- ✨ `feature-request` (blue) - For feature requests  
- 📱 `user-submitted` (yellow) - For app-submitted issues
- ✅ `completed` (green) - For implemented features
- 🔄 `in-progress` (orange) - For work in progress

### Issue Templates (Optional)

Create `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug Report
about: Report a bug from the mobile app
labels: bug, user-submitted
---

**Device Info:**
- Device: 
- iOS Version: 
- App Version: 

**Description:**
<!-- Bug description -->

**Steps to Reproduce:**
1. 
2. 
3. 

**Expected vs Actual Behavior:**
<!-- What should happen vs what actually happened -->
```

## Troubleshooting

### Common Issues

**No issues loading:**
- Verify your GitHub token has correct permissions
- Check that repository name and owner are correct
- Ensure repository exists and is accessible

**Voting not working:**
- Confirm token has "Issues: Write" permission
- Check network connectivity
- Verify issue exists and is accessible

**Duplicate vote prevention not working:**
- UserDefaults data may have been cleared
- Device identifier may have changed (rare)

### Debug Mode

```swift
// Enable debug logging
await gitHubService.loadIssues(type: .all)
print("Loaded \(gitHubService.issues.count) issues")

// Check voting status
let votingService = VotingService()
print("User has voted on: \(votingService.getVotedIssues())")
```

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
