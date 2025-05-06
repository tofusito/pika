import SwiftUI

/// Markdown Guide
struct MarkdownView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Process text line by line to handle headers, lists, etc.
            ForEach(Array(parseMarkdown(text).enumerated()), id: \.offset) { _, element in
                element
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    
    /// Applies underline to links in an AttributedString
    private func underlineLinks(_ attributed: AttributedString) -> AttributedString {
        var mutableAttributed = attributed
        
        // Find all links in the AttributedString
        mutableAttributed.runs.forEach { run in
            // Check if this run has a link attribute
            if let _ = run.link {
                // Underline this run
                mutableAttributed[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
            }
        }
        
        return mutableAttributed
    }
    
    /// Parses Markdown text and returns a list of views
    private func parseMarkdown(_ markdown: String) -> [AnyView] {
        var result: [AnyView] = []
        let lines = markdown.components(separatedBy: .newlines)
        
        // Process multiline code blocks
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeLanguage = ""
        
        // Process tables
        var inTable = false
        var tableRows: [[String]] = []
        
        var i = 0
        while i < lines.count {
            let line = lines[i]
            
            // Handle code blocks
            if line.hasPrefix("```") {
                if !inCodeBlock {
                    // Start of code block
                    inCodeBlock = true
                    codeLanguage = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeBlockContent = ""
                } else {
                    // End of code block
                    inCodeBlock = false
                    result.append(renderCodeBlock(codeBlockContent, language: codeLanguage))
                }
                i += 1
                continue
            }
            
            if inCodeBlock {
                codeBlockContent += line + "\n"
                i += 1
                continue
            }

            // Handle tables
            if line.contains("|") {
                if !inTable {
                    // Possible table start
                    let cells = parseCells(from: line)
                    if !cells.isEmpty {
                        inTable = true
                        tableRows = [cells]
                    }
                } else if line.contains("|-") {
                    // Separator line, ignore
                } else {
                    // Table row
                    let cells = parseCells(from: line)
                    if !cells.isEmpty {
                        tableRows.append(cells)
                    } else {
                        // End of table
                        result.append(renderTable(tableRows))
                        tableRows = []
                        inTable = false
                    }
                }
                i += 1
                continue
            } else if inTable {
                // End of table
                result.append(renderTable(tableRows))
                tableRows = []
                inTable = false
            }
            
            // Normal line by line processing
            result.append(parseLine(line))
            i += 1
        }
        
        // If we end the file and there's still an open table
        if inTable && !tableRows.isEmpty {
            result.append(renderTable(tableRows))
        }
        
        // If we end the file and there's still an open code block
        if inCodeBlock {
            result.append(renderCodeBlock(codeBlockContent, language: codeLanguage))
        }
        
        return result
    }
    
    /// Renders a single line of Markdown
    private func parseLine(_ line: String) -> AnyView {
        // Checkbox - incomplete task
        if line.range(of: #"^[-*] \[ \]"#, options: .regularExpression) != nil {
            let task = line.replacingOccurrences(of: #"^[-*] \[ \] "#, with: "", options: .regularExpression)
            return AnyView(
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "square")
                        .foregroundColor(.gray)
                    Text(task)
                }
                .padding(.vertical, 2)
            )
        }
        // Checkbox - completed task
        else if line.range(of: #"^[-*] \[x\]"#, options: .regularExpression, range: nil, locale: nil) != nil ||
                line.range(of: #"^[-*] \[X\]"#, options: .regularExpression, range: nil, locale: nil) != nil {
            let task = line.replacingOccurrences(of: #"^[-*] \[[xX]\] "#, with: "", options: .regularExpression)
            return AnyView(
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundColor(.blue)
                    Text(task)
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            )
        }
        // H1 header
        else if line.hasPrefix("# ") {
            let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)
            )
        }
        // H2 header
        else if line.hasPrefix("## ") {
            let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.bottom, 2)
            )
        }
        // H3 header
        else if line.hasPrefix("### ") {
            let title = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            )
        }
        // H4 header
        else if line.hasPrefix("#### ") {
            let title = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
            )
        }
        // H5 header
        else if line.hasPrefix("##### ") {
            let title = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.footnote)
                    .fontWeight(.bold)
            )
        }
        // H6 header
        else if line.hasPrefix("###### ") {
            let title = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return AnyView(
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
            )
        }
        // Bullet lists
        else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            let item = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    if let attributed = try? AttributedString(markdown: item, options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )) {
                        // Underline links in lists
                        Text(underlineLinks(attributed))
                    } else {
                        Text(item)
                    }
                }
                .padding(.leading, 8)
            )
        }
        // Numbered lists (simplified)
        else if line.range(of: "^\\d+\\. ", options: .regularExpression) != nil,
                let dotIndex = line.firstIndex(of: "."),
                dotIndex < line.endIndex {
            let number = String(line[..<dotIndex])
            let item = line[line.index(dotIndex, offsetBy: 2)...].trimmingCharacters(in: .whitespaces)
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    Text("\(number).")
                        .frame(width: 20, alignment: .trailing)
                    if let attributed = try? AttributedString(markdown: item, options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )) {
                        // Underline links in numbered lists
                        Text(underlineLinks(attributed))
                    } else {
                        Text(item)
                    }
                }
                .padding(.leading, 8)
            )
        }
        // Inline code
        else if line.hasPrefix("    ") || line.hasPrefix("\t") {
            let code = line.hasPrefix("    ") ? line.dropFirst(4) : line.dropFirst(1)
            return AnyView(
                Text(String(code))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(4)
            )
        }
        // Horizontal line
        else if line.hasPrefix("---") || line.hasPrefix("***") || line.hasPrefix("___") {
            return AnyView(
                Divider()
                    .padding(.vertical, 8)
            )
        }
        // Quotes
        else if line.hasPrefix("> ") {
            let quote = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return AnyView(
                HStack {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 4)
                    if let attributed = try? AttributedString(markdown: quote, options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )) {
                        // Underline links in quotes
                        Text(underlineLinks(attributed))
                            .padding(.leading, 8)
                    } else {
                        Text(quote)
                            .italic()
                            .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 4)
            )
        }
        // Empty line
        else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return AnyView(
                Spacer()
                    .frame(height: 8)
            )
        }
        // Normal text
        else {
            // Try first with AttributedString for inline formatting
            if let attributed = try? AttributedString(markdown: line, options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )) {
                // Modify AttributedString to underline links
                return AnyView(Text(underlineLinks(attributed)))
            } else {
                return AnyView(Text(line))
            }
        }
    }
    
    /// Parses cells from a table line
    private func parseCells(from line: String) -> [String] {
        // Remove first and last pipe if they exist
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed = String(trimmed.dropFirst())
        }
        if trimmed.hasSuffix("|") {
            trimmed = String(trimmed.dropLast())
        }
        
        // Split by pipe and remove spaces
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    /// Renders a complete table
    private func renderTable(_ rows: [[String]]) -> AnyView {
        guard !rows.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Render rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                    HStack(spacing: 0) {
                        // Render cells
                        ForEach(Array(cells.enumerated()), id: \.offset) { colIndex, cell in
                            VStack {
                                if let attributed = try? AttributedString(markdown: cell, options: AttributedString.MarkdownParsingOptions(
                                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                                )) {
                                    // Underline links in table cells
                                    Text(underlineLinks(attributed))
                                } else {
                                    Text(cell)
                                }
                            }
                            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(rowIndex == 0 ? Color(.secondarySystemBackground) : Color.clear)
                            .border(Color.gray.opacity(0.3), width: 0.5)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color.clear)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        )
    }
    
    /// Renders a code block
    private func renderCodeBlock(_ code: String, language: String) -> AnyView {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                // Programming language
                if !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                
                // Code
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(trimmedCode)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.layoutDirection, .leftToRight)
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        )
    }
} 