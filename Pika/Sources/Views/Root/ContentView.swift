import SwiftUI

/// Navigation item: folder or note
enum FileNavigationItem: Hashable {
    case directory(URL)
    case note(url: URL, autoFocus: Bool)
}

/// Simple model to represent a file or folder
struct FileItem: Hashable {
    let url: URL
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

struct ContentView: View {
    private let rootURL: URL = {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let notesURL = documents.appendingPathComponent("Pikas", isDirectory: true)
        if !fm.fileExists(atPath: notesURL.path) {
            try? fm.createDirectory(at: notesURL, withIntermediateDirectories: true)
        }
        return notesURL
    }()

    @State private var navigationPath: [FileNavigationItem] = []
    @AppStorage("isDarkMode") private var isDarkMode = true
    @EnvironmentObject private var floatingButtonStore: FloatingButtonStore
    
    // FolderContentView state properties
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
    private let errorStripeHeight: CGFloat = 32

    var body: some View {
        NavigationStack(path: $navigationPath) {
            contentList(for: rootURL)
                .navigationTitle(currentDirectoryURL() == rootURL ? "Pikas" : currentDirectoryURL().lastPathComponent)
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
                
            .navigationDestination(for: FileNavigationItem.self) { item in
                switch item {
                case .directory(let url):
                    contentList(for: url)
                        .navigationTitle(url.lastPathComponent)
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar { toolbarItems }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .note(let url, let autoFocus):
                    NoteDetailView(noteURL: url, autoFocus: autoFocus) { oldURL, newURL in
                        if let idx = navigationPath.firstIndex(where: { nav in
                            if case .note(let u, _) = nav, u == oldURL { return true }
                            return false
                        }) {
                            navigationPath[idx] = .note(url: newURL, autoFocus: false)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .scale(scale: 0.95))
                    ))
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .tint(.primary)
        .background(
            (isDarkMode ? Color.black : Color.white)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .onAppear {
            setupFloatingButton()
        }
        .onChange(of: navigationPath) { oldValue, newValue in
            setupFloatingButton()
        }
    }
    
    // Content list view for a specific directory
    @ViewBuilder
    private func contentList(for directoryURL: URL) -> some View {
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    deleteNote(subItem.url)
                                } label: {
                                    Text("Eliminar")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                }
                                .tint(Color(red: 0.8, green: 0.2, blue: 0.2))
                            }
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deleteNote(item.url)
                        } label: {
                            Text("Eliminar")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                        }
                        .tint(Color(red: 0.8, green: 0.2, blue: 0.2))
                    }
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
            
    // Helper to get the current folder URL from navigationPath
    private func currentDirectoryURL() -> URL {
        if let last = navigationPath.last, case .directory(let url) = last {
            return url
        }
        return rootURL
    }
    
    // Check if we are viewing a note
    private func isViewingNote() -> Bool {
        if let last = navigationPath.last, case .note = last {
            return true
        }
        return false
    }
    
    // Configure the floating button based on current context
    private func setupFloatingButton() {
        if isViewingNote() {
            // In note view, hide the button and let NoteDetailView configure it
            // This avoids conflicts during transition
            floatingButtonStore.hide()
        } else {
            // In folders view, configure to add notes
            floatingButtonStore.setupForAddNote(
                folderURL: currentDirectoryURL(), 
                createCallback: createNewNote
            )
        }
    }
        
    // Create note in the current folder
    private func createNewNote(in url: URL) {
        let fm = FileManager.default
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = df.string(from: Date()) + ".md"
        let noteURL = url.appendingPathComponent(name)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        withAnimation { navigationPath.append(.note(url: noteURL, autoFocus: true)) }
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
                if !isSelecting {
                    selectedNotes.removeAll()
                }
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
        isSelecting = false
        selectedNotes.removeAll()
        listRefreshID = UUID() // Force refresh the list
    }

    private func createNewFolder() {
        guard !newFolderName.isEmpty else { return }

        let fm = FileManager.default
        let url = currentDirectoryURL().appendingPathComponent(newFolderName, isDirectory: true)

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
            if !fm.fileExists(atPath: currentDirectoryURL().path) {
                try fm.createDirectory(at: currentDirectoryURL(), withIntermediateDirectories: true, attributes: nil)
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
            }
        } catch {
            print("Error creating directory: \(error.localizedDescription)")
        }
    }

    // Función para eliminar una nota
    private func deleteNote(_ url: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
            // Forzar actualización de la lista
            listRefreshID = UUID()
        } catch {
            print("Error al eliminar nota: \(error.localizedDescription)")
        }
    }
}

// Folder row with inline toggle and navigation button
struct FolderRow: View {
    let url: URL
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNavigate: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 22))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 30)
            
            Text(url.lastPathComponent)
                .font(.system(size: 18, weight: .medium))
                .padding(.vertical, 12)
            
            Spacer()
            
            Button {
                onNavigate(url)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// Note row that navigates to the editor
struct NoteRow: View {
    let url: URL
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 20))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 30)
            
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 17))
                .padding(.vertical, 12)
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
} 