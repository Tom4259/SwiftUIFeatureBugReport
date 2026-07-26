//
//  FeedbackFormView.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import SwiftUI

public struct FeedbackFormView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    private let gitHubService: GitHubService
    private let issueToEdit: GitHubIssue?
    private let ownershipService: IssueOwnershipService
    
    
    @State private var title = ""
    @State private var description = ""
    @State private var contactEmail = ""
    @State private var selectedType: IssueType
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    public init(gitHubService: GitHubService,
                selectedType: IssueType,
                issueToEdit: GitHubIssue? = nil,
                ownershipService: IssueOwnershipService = IssueOwnershipService()) {
            
        self.gitHubService = gitHubService
        self.issueToEdit = issueToEdit
        self.ownershipService = ownershipService
        
        // Pre-populate if editing
        if let issue = issueToEdit, issue.state == "open" {
            
            self.selectedType = issue.isFeatureRequest ? .features : .bugs
            
            _title = State(initialValue: issue.title)
            _description = State(initialValue: issue.displayableBody ?? "")
        }
        else {
            
            self.selectedType = selectedType == .all ? .bugs : selectedType
        }
    }
    
    public var body: some View {
        
        NavigationStack {
            
            Form {
                
                Section(header: Text("Feedback Type")) {
                    
                    Picker("Type", selection: $selectedType) {
                        
                        Text("Bug Report").tag(IssueType.bugs)
                        Text("Feature Request").tag(IssueType.features)
                    }
                    .pickerStyle(.segmented)
                    .disabled(issueToEdit != nil)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                
                Section(header: Text("Details")) {
                    
                    TextField("Title", text: $title)
                    
                    VStack(alignment: .leading) {
                        
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $description)
                            .frame(minHeight: 100)
                    }
                }
                
                Section(content: {
                    
                    TextField("Email", text: $contactEmail)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                }, header: { Text("Contact Email (optional)") },
                        footer: { Text("To contact you for more details") })
                
                
                Section(footer: Text("Device information will be automatically included")) {
                    
                    Button("Submit \(selectedType == .bugs ? "Bug Report" : "Feature Request")") {
                        
                        Task { await submitFeedback() }
                    }
                    .disabled(title.isEmpty || description.isEmpty || isSubmitting)
                }
                
                if isSubmitting {
                    
                    Section {
                        
                        HStack {
                            
                            ProgressView()
                                .scaleEffect(0.8)
                            
                            Text("Submitting...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Feedback")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    
                    Button("Cancel") { dismiss() }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    
                    Button("Cancel") { dismiss() }
                }
                #endif
            }
            
            .alert("Success!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your \(selectedType == .bugs ? "bug report" : "feature request") has been submitted. Thank you!")
            }
            
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func submitFeedback() async {
        
        isSubmitting = true
        
        do {
            
            let deviceInfo = DeviceInfo.generateReport()
            
            if let issue = issueToEdit {
                
                // Update existing issue
                try await gitHubService.updateIssueContent(
                    number: issue.number,
                    title: title,
                    description: description,
                    type: selectedType,
                    deviceInfo: deviceInfo,
                    contactEmail: contactEmail.isEmpty ? nil : contactEmail
                )
            }
            else {
                
                // Create new issue
                let issueNumber = try await gitHubService.createIssue(
                    title: title,
                    description: description,
                    type: selectedType,
                    deviceInfo: deviceInfo,
                    contactEmail: contactEmail.isEmpty ? nil : contactEmail
                )
                
                // Mark as owned
                ownershipService.markAsOwned(issueNumber)
            }
            
            showSuccess = true
            
        }
        catch {
            
            errorMessage = error.localizedDescription
        }
        
        isSubmitting = false
    }
}
