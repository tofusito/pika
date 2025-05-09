import SwiftUI

/// Markdown Guide
struct MarkdownGuideView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        sectionHeader("Markdown Quick Reference")
                        
                        markdownSection("Headers", examples: [
                            "# Heading 1",
                            "## Heading 2",
                            "### Heading 3"
                        ])
                        
                        markdownSection("Emphasis", examples: [
                            "*Italic* or _Italic_",
                            "**Bold** or __Bold__",
                            "~~Strikethrough~~"
                        ])
                        
                        markdownSection("Lists", examples: [
                            "- Unordered item",
                            "* Alternative unordered item",
                            "1. Ordered item",
                            "2. Second ordered item"
                        ])
                        
                        markdownSection("Checklists", examples: [
                            "- [ ] Unchecked item",
                            "- [x] Checked item"
                        ])
                    }
                    
                    Group {
                        markdownSection("Links", examples: [
                            "[Link text](https://example.com)",
                            "[Link with title](https://example.com \"Title\")"
                        ])
                        
                        markdownSection("Images", examples: [
                            "![Alt text](image-url.jpg)",
                            "![Alt with title](image-url.jpg \"Title\")"
                        ])
                        
                        markdownSection("Blockquotes", examples: [
                            "> This is a blockquote",
                            "> Multi-line blockquote",
                            "> Another line"
                        ])
                        
                        markdownSection("Code", examples: [
                            "`Inline code` with backticks",
                            "```",
                            "// Code block",
                            "function example() {",
                            "    return true;",
                            "}",
                            "```"
                        ])
                        
                        markdownSection("Tables", examples: [
                            "| Header 1 | Header 2 |",
                            "|----------|----------|",
                            "| Cell 1   | Cell 2   |",
                            "| Cell 3   | Cell 4   |"
                        ])
                        
                        markdownSection("Horizontal Rule", examples: [
                            "---",
                            "***",
                            "___"
                        ])
                    }
                }
                .padding()
            }
            .environment(\.layoutDirection, .leftToRight)
            .scrollIndicators(.hidden)
            .navigationTitle("Markdown Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title)
            .fontWeight(.bold)
            .padding(.bottom, 4)
    }
    
    private func markdownSection(_ title: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(examples, id: \.self) { example in
                    Text(example)
                        .font(.system(.body, design: .monospaced))
                        .padding(4)
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            if let firstExample = examples.first {
                if !firstExample.hasPrefix("```") && !firstExample.hasPrefix("|") {
                    Text("Result:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    if let rendered = try? AttributedString(markdown: examples.joined(separator: "\n")) {
                        Text(rendered)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
            
            Divider()
                .padding(.top, 8)
        }
    }
} 