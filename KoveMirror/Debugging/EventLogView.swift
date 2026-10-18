import SwiftUI

struct EventLogView: View {
    @ObservedObject var bleController: BleController
    @Environment(\.dismiss) private var dismiss
    @State private var copiedNotice = false
    @State private var searchText = ""
    
    var filteredLogs: [String] {
        if searchText.isEmpty {
            return bleController.logMessages
        } else {
            return bleController.logMessages.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background dark gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0D0D11"), Color(hex: "1F1F2E")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header Summary & Actions Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostic Terminal")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(bleController.logMessages.count) log events recorded")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        // Copy Log Button
                        Button(action: copyLogsToClipboard) {
                            HStack(spacing: 6) {
                                Image(systemName: copiedNotice ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(copiedNotice ? "Copied!" : "Copy Log")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(copiedNotice ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            .foregroundColor(copiedNotice ? .green : .blue)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(copiedNotice ? Color.green.opacity(0.4) : Color.blue.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.4))
                        TextField("Search logs...", text: $searchText)
                            .foregroundColor(.white)
                            .font(.subheadline)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Log Terminal Content
                    if filteredLogs.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "terminal")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.2))
                            Text("No log events match your query.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, msg in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(String(format: "%03d", filteredLogs.count - index))
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.3))
                                                .frame(width: 28, alignment: .trailing)
                                            
                                            Text(msg)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(logColor(for: msg))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding()
                            }
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Event Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func logColor(for msg: String) -> Color {
        if msg.contains("❌") || msg.contains("⚠️") || msg.contains("error") {
            return Color.red.opacity(0.9)
        } else if msg.contains("🟢") || msg.contains("✅") || msg.contains("connected") {
            return Color.green.opacity(0.9)
        } else if msg.contains("📺") || msg.contains("🔌") || msg.contains("BLE") {
            return Color.cyan.opacity(0.9)
        } else {
            return Color.white.opacity(0.85)
        }
    }
    
    private func copyLogsToClipboard() {
        let fullText = bleController.logMessages.joined(separator: "\n")
        UIPasteboard.general.string = fullText
        
        withAnimation {
            copiedNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedNotice = false
            }
        }
    }
}
