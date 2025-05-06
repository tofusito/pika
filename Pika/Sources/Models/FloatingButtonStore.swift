import SwiftUI
import Combine

/// Tipo de acción que puede realizar el botón flotante
enum FloatingButtonAction {
    case addNote           // Añadir nueva nota
    case transformNote     // Transformar nota con IA
    case showSuggestions   // Mostrar sugerencias guardadas
    case none              // Sin acción (oculto)
}

/// Store para controlar el estado y comportamiento del botón flotante global
class FloatingButtonStore: ObservableObject {
    /// Singleton compartido
    static let shared = FloatingButtonStore()
    
    /// Acción actual que realiza el botón
    @Published var currentAction: FloatingButtonAction = .addNote
    
    /// Carpeta actual para crear notas
    @Published var currentFolderURL: URL?
    
    /// URL de la nota actual para transformaciones
    @Published var currentNoteURL: URL?
    
    /// Indica si el botón está visible
    @Published var isVisible: Bool = true
    
    /// Indica si el botón está en modo de carga
    @Published var isLoading: Bool = false
    
    /// Indica si hay texto modificado desde la última transformación
    @Published var textModifiedSinceTransform: Bool = false
    
    /// Indica si hay sugerencias guardadas para la nota actual
    @Published var hasSavedSuggestions: Bool = false
    
    /// Callback para crear una nota
    var createNoteCallback: ((URL) -> Void)?
    
    /// Callback para transformar una nota
    var transformNoteCallback: (() -> Void)?
    
    /// Callback para mostrar sugerencias
    var showSuggestionsCallback: (() -> Void)?
    
    /// Constructor privado para singleton
    private init() {}
    
    /// Configura el botón para añadir notas
    func setupForAddNote(folderURL: URL, createCallback: @escaping (URL) -> Void) {
        DispatchQueue.main.async {
            withAnimation {
                self.currentAction = .addNote
                self.currentFolderURL = folderURL
                self.createNoteCallback = createCallback
                self.isVisible = true
                self.isLoading = false
            }
        }
    }
    
    /// Configura el botón para transformar notas
    func setupForTransformNote(
        noteURL: URL,
        transformCallback: @escaping () -> Void,
        showSuggestionsCallback: @escaping () -> Void,
        hasSavedSuggestions: Bool = false,
        textModified: Bool = false
    ) {
        DispatchQueue.main.async {
            withAnimation {
                self.currentNoteURL = noteURL
                self.transformNoteCallback = transformCallback
                self.showSuggestionsCallback = showSuggestionsCallback
                self.hasSavedSuggestions = hasSavedSuggestions
                self.textModifiedSinceTransform = textModified
                
                // Determinar la acción basada en si hay sugerencias guardadas y si el texto ha sido modificado
                if hasSavedSuggestions && !textModified {
                    self.currentAction = .showSuggestions
                } else {
                    self.currentAction = .transformNote
                }
                
                self.isVisible = true
                self.isLoading = false
            }
        }
    }
    
    /// Oculta el botón (para vistas de settings, etc.)
    func hide() {
        DispatchQueue.main.async {
            withAnimation {
                self.isVisible = false
                self.currentAction = .none
            }
        }
    }
    
    /// Actualiza el estado de carga
    func setLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.isLoading = loading
            }
        }
    }
    
    /// Ejecuta la acción actual del botón
    func executeAction() {
        switch currentAction {
        case .addNote:
            if let url = currentFolderURL, let callback = createNoteCallback {
                callback(url)
            }
        case .transformNote:
            if let callback = transformNoteCallback {
                callback()
            }
        case .showSuggestions:
            if let callback = showSuggestionsCallback {
                callback()
            }
        case .none:
            break
        }
    }
} 