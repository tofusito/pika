import SwiftUI

/// Item de navegación: carpeta o nota
enum FileNavigationItem: Hashable {
    case directory(URL)
    case note(url: URL, autoFocus: Bool)
}

/// Modelo sencillo para representar un archivo o carpeta
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

    var body: some View {
        // NavigationStack sin el botón flotante
        NavigationStack(path: $navigationPath) {
            // Listado de carpetas y notas
            FolderContentView(
                rootURL: rootURL,
                directoryURL: currentDirectoryURL(),
                navigationPath: $navigationPath
            )
            // Destinos de navegación para carpetas y notas dentro de la pila
            .navigationDestination(for: FileNavigationItem.self) { item in
                switch item {
                case .directory(let url):
                    FolderContentView(rootURL: rootURL, directoryURL: url, navigationPath: $navigationPath)
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
            // Configurar el botón flotante para añadir notas en la carpeta actual
            setupFloatingButton()
        }
        .onChange(of: navigationPath) { oldValue, newValue in
            // Actualizar el botón cuando cambia la navegación
            setupFloatingButton()
        }
    }
            
    // Helper para obtener la URL de la carpeta actual desde navigationPath
    private func currentDirectoryURL() -> URL {
        if let last = navigationPath.last, case .directory(let url) = last {
            return url
        }
        return rootURL
    }
    
    // Verifica si estamos viendo una nota
    private func isViewingNote() -> Bool {
        if let last = navigationPath.last, case .note = last {
            return true
        }
        return false
    }
    
    // Configurar el botón flotante según el contexto actual
    private func setupFloatingButton() {
        if isViewingNote() {
            // En la vista de nota, ocultamos el botón y dejamos que NoteDetailView lo configure
            // Esto evita conflictos durante la transición
            floatingButtonStore.hide()
        } else {
            // En vista de carpetas, configuramos para añadir notas
            floatingButtonStore.setupForAddNote(
                folderURL: currentDirectoryURL(), 
                createCallback: createNewNote
            )
        }
    }
        
    // Crear nota en la carpeta actual
    private func createNewNote(in url: URL) {
        let fm = FileManager.default
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = df.string(from: Date()) + ".md"
        let noteURL = url.appendingPathComponent(name)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        withAnimation { navigationPath.append(.note(url: noteURL, autoFocus: true)) }
    }
}

// Removed old fileListView, helper methods, and state properties in favor of FolderContentView

// Fila para carpeta con toggle inline y botón de navegación
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

// Fila para nota que navega al editor
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