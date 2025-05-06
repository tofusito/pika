import SwiftUI

/// A reusable view for displaying folder contents and notes, encapsulating folder navigation and actions.
struct FolderContentView: View {
    let rootURL: URL
    let directoryURL: URL
    @Binding var navigationPath: [FileNavigationItem]

    @State private var expandedInline: Set<URL> = []
    @State private var showNewFolderField = false
    @State private var newFolderName = ""
    @FocusState private var isNewFolderFieldFocused: Bool
    @State private var isSelecting = false
    @State private var selectedNotes: Set<URL> = []
    @State private var showMoveSheetForSelection = false
    @State private var showSettings = false
    @State private var showAppInfo = false
    @State private var showErrorStripe = false
    @State private var showErrorText = false
    @State private var listRefreshID = UUID()
    @AppStorage("isDarkMode") private var isDarkMode = true
    private let errorStripeHeight: CGFloat = 32

    var body: some View {
        contentList
        .navigationTitle(directoryURL == rootURL ? "Pikas" : directoryURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showMoveSheetForSelection) {
            moveSheetView
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .tint(.primary)
        }
        .sheet(isPresented: $showAppInfo) {
            AppInfoView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .tint(.primary)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .tint(.primary)
        .background((isDarkMode ? Color.black : Color.white).ignoresSafeArea())
    }

    private var contentList: some View {
        List {
            // New folder field
            if showNewFolderField {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(.primary)

                        TextField("Folder name", text: $newFolderName)
                            .font(.body)
                            .focused($isNewFolderFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { createNewFolder() }

                        Button(action: createNewFolder) {
                            Text("Create")
                                .font(.headline)
                                .foregroundColor(Color(UIColor.systemBackground))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(UIColor.label)))
                        }
                        .disabled(newFolderName.isEmpty)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showNewFolderField = false
                                newFolderName = ""
                                showErrorStripe = false
                                showErrorText = false
                            }
                            isNewFolderFieldFocused = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)

                    VStack {
                        if showErrorText {
                            Text("Folder name already in use")
                                .font(.caption)
                                .foregroundColor(isDarkMode ? .white.opacity(0.9) : .black.opacity(0.9))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isDarkMode ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                                .cornerRadius(4)
                                .opacity(showErrorText ? 1 : 0)
                                .animation(.easeInOut(duration: 0.4), value: showErrorText)
                        }
                    }
                    .frame(height: showErrorStripe ? errorStripeHeight : 0)
                    .clipped()
                    .animation(.easeInOut(duration: 0.6), value: showErrorStripe)
                }
                .listRowBackground(isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Directory and note items
            let items = fetchItems(in: directoryURL)
            let dirs = items.filter { $0.isDirectory }
            let notes = items.filter { !$0.isDirectory }

            ForEach(dirs, id: \.url) { item in
                FolderRow(
                    url: item.url,
                    isExpanded: expandedInline.contains(item.url)
                ) {
                    withAnimation {
                        if expandedInline.contains(item.url) {
                            expandedInline.remove(item.url)
                        } else {
                            expandedInline.insert(item.url)
                        }
                    }
                } onNavigate: { selectedURL in
                    navigationPath.append(.directory(selectedURL))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)

                if expandedInline.contains(item.url) {
                    let children = fetchItems(in: item.url)
                    let subDirs = children.filter { $0.isDirectory }
                    let subNotes = children.filter { !$0.isDirectory }

                    ForEach(subDirs, id: \.url) { subItem in
                        FolderRow(
                            url: subItem.url,
                            isExpanded: expandedInline.contains(subItem.url)
                        ) {
                            withAnimation {
                                if expandedInline.contains(subItem.url) {
                                    expandedInline.remove(subItem.url)
                                } else {
                                    expandedInline.insert(subItem.url)
                                }
                            }
                        } onNavigate: { url in
                            navigationPath.append(.directory(url))
                        }
                        .padding(.leading, 20)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    ForEach(subNotes, id: \.url) { subItem in
                        if isSelecting {
                            HStack {
                                Image(systemName: selectedNotes.contains(subItem.url) ? "checkmark.circle.fill" : "circle")
                                    .onTapGesture { toggleSelection(subItem.url) }
                                NoteRow(url: subItem.url) {
                                    toggleSelection(subItem.url)
                                }
                            }
                            .padding(.leading, 20)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            .listRowBackground(Color.clear)
                        } else {
                            NoteRow(url: subItem.url) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    navigationPath.append(.note(url: subItem.url, autoFocus: false))
                                }
                            }
                            .padding(.leading, 20)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }

            ForEach(notes, id: \.url) { item in
                if isSelecting {
                    HStack {
                        Image(systemName: selectedNotes.contains(item.url) ? "checkmark.circle.fill" : "circle")
                            .onTapGesture { toggleSelection(item.url) }
                        NoteRow(url: item.url) {
                            toggleSelection(item.url)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                } else {
                    NoteRow(url: item.url) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            navigationPath.append(.note(url: item.url, autoFocus: false))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .id(listRefreshID)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background((isDarkMode ? Color.black : Color.white).ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 60)
        .listRowSeparator(.hidden)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Main actions group in the navigation bar
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Create new folder
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showNewFolderField = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isNewFolderFieldFocused = true
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white : .black)
            }

            // Selection mode
            Button {
                isSelecting.toggle()
            } label: {
                Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white : .black)
            }

            // Options menu (Settings, Info)
            Menu {
                Button("Settings") { showSettings = true }
                Button("Info") { showAppInfo = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17))
                    .foregroundColor(isDarkMode ? .white : .black)
            }
        }
        // Move selected button in the bottom bar
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showMoveSheetForSelection = true
                } label: {
                    Text("Move")
                        .font(.headline)
                        .foregroundColor(isDarkMode ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
                .disabled(selectedNotes.isEmpty)
                .opacity(selectedNotes.isEmpty ? 0.5 : 1.0)
            }
        }
    }

    private var moveSheetView: some View {
        NavigationStack {
            List(allDirectories(in: rootURL), id: \.self) { dir in
                Text(dir.lastPathComponent)
                    .onTapGesture {
                        moveSelectedNotes(to: dir)
                        showMoveSheetForSelection = false
                    }
            }
            .navigationTitle("Move to…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showMoveSheetForSelection = false }
                }
            }
        }
    }

    private func fetchItems(in url: URL) -> [FileItem] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let fileItems = urls.map { FileItem(url: $0) }
        return fileItems.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                $1.url.lastPathComponent
            ) == .orderedAscending
        }
    }

    private func createNewNote(autoFocus: Bool = false) {
        let fm = FileManager.default
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = df.string(from: Date()) + ".md"
        let url = directoryURL.appendingPathComponent(name)

        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            navigationPath.append(.note(url: url, autoFocus: autoFocus))
        }
    }

    private func cancelSelection() {
        isSelecting = false
        selectedNotes.removeAll()
    }

    private func toggleSelection(_ url: URL) {
        if selectedNotes.contains(url) {
            selectedNotes.remove(url)
        } else {
            selectedNotes.insert(url)
        }
    }

    private func allDirectories(in url: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var dirs: [URL] = []
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                dirs.append(fileURL)
            }
        }
        return dirs.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func moveSelectedNotes(to destination: URL) {
        let fm = FileManager.default
        for url in selectedNotes {
            let newURL = destination.appendingPathComponent(url.lastPathComponent)
            try? fm.moveItem(at: url, to: newURL)
        }
        cancelSelection()
    }

    private func createNewFolder() {
        guard !newFolderName.isEmpty else { return }

        let fm = FileManager.default
        let url = directoryURL.appendingPathComponent(newFolderName, isDirectory: true)

        if fm.fileExists(atPath: url.path) {
            let stripeDuration = 0.6
            let textDuration = 0.4

            withAnimation(.easeInOut(duration: stripeDuration)) {
                showErrorStripe = true
                showErrorText = true
            }
            newFolderName = ""
            isNewFolderFieldFocused = true

            DispatchQueue.main.asyncAfter(deadline: .now() + stripeDuration + 3) {
                withAnimation(.easeInOut(duration: textDuration)) {
                    showErrorText = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + textDuration) {
                    withAnimation(.easeInOut(duration: stripeDuration)) {
                        showErrorStripe = false
                    }
                }
            }
            return
        }

        showErrorText = false
        showErrorStripe = false

        do {
            if !fm.fileExists(atPath: directoryURL.path) {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Directory created at \(directoryURL.path)")
            }

            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            if fm.fileExists(atPath: url.path) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    newFolderName = ""
                    showNewFolderField = false
                    isNewFolderFieldFocused = false
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    navigationPath.append(.directory(url))
                }
            } else {
                print("Failed to create directory at: \(url.path)")
            }
        } catch {
            print("Error creating directory: \(error.localizedDescription)")
        }
    }
} 