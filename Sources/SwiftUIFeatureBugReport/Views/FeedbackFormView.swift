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
    
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedType: IssueType
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    public init(gitHubService: GitHubService, selectedType: IssueType) {
        
        self.gitHubService = gitHubService
        self.selectedType = selectedType == .all ? .bugs : selectedType
    }
    
    public var body: some View {
        
        NavigationView {
            
            Form {
                
                Section(header: Text("Feedback Type")) {
                    
                    Picker("Type", selection: $selectedType) {
                        
                        Text("Bug Report").tag(IssueType.bugs)
                        Text("Feature Request").tag(IssueType.features)
                    }
                    .pickerStyle(.segmented)
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
                
                
                Section(footer: Text("Device information will be automatically included")) {
                    
                    Button("Submit \(selectedType == .bugs ? "Bug Report" : "Feature Request")") {
                        
                        Task {
                            
                            await submitFeedback()
                        }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .navigationBarLeading) {
                    
                    Button("Cancel") { dismiss() }
                }
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
            try await gitHubService.createIssue(
                title: title,
                description: description,
                type: selectedType,
                deviceInfo: deviceInfo
            )
            
            showSuccess = true
            
        }
        catch {
            
            errorMessage = error.localizedDescription
        }
        
        isSubmitting = false
    }
}
