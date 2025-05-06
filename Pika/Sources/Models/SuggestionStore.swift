import Foundation
import SwiftUI
import Combine

/// Estructura para almacenar sugerencias por nota
struct NoteSuggestions: Codable {
    let formatted: String
    let suggestions: [String]
    let timestamp: Date
    var textModified: Bool?
    
    init(formatted: String, suggestions: [String], textModified: Bool = false) {
        self.formatted = formatted
        self.suggestions = suggestions
        self.timestamp = Date()
        self.textModified = textModified
    }
}

/// Store para manejar las sugerencias y su visibilidad
class SuggestionStore: ObservableObject {
    /// Singleton compartido
    static let shared = SuggestionStore()
    
    /// Sugerencias actuales
    @Published var suggestions: [String] = []
    
    /// Indica si la vista de sugerencias debe mostrarse
    @Published var isVisible: Bool = false
    
    /// Indica si la vista está en proceso de animación (apareciendo o desapareciendo)
    @Published var isAnimating: Bool = false
    
    /// Texto formateado actual de la nota (para poder aplicar sugerencias)
    @Published var currentFormattedText: String? = nil
    
    /// URL de la nota actual
    @Published var currentNoteURL: URL? = nil
    
    /// Nueva propiedad para indicar que se ha solicitado mostrar la vista de entrada personalizada
    @Published var showCustomInputRequested: Bool = false
    
    /// Almacenamiento de sugerencias por URL de nota
    private var noteSuggestionsCache: [String: NoteSuggestions] = [:]
    
    /// Clave para UserDefaults
    private let suggestionsStorageKey = "com.pika.noteSuggestions"
    
    /// Token de cancelación para manejo de suscripciones
    private var cancellables = Set<AnyCancellable>()
    
    /// Constructor privado para singleton
    private init() {
        // Asegurar que todo esté oculto al inicio
        isVisible = false
        isAnimating = false
        suggestions = []
        
        // Cargar sugerencias guardadas
        loadAllSavedSuggestions()
        
        // Escuchar eventos de aplicación para manejar el ciclo de vida
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.hideSuggestions()
                self?.saveAllSuggestions() // Guardar al salir de la app
            }
            .store(in: &cancellables)
            
        // También guardar cuando la app termina
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.saveAllSuggestions()
            }
            .store(in: &cancellables)
    }
    
    /// Establece nuevas sugerencias y muestra la vista
    func setSuggestions(_ newSuggestions: [String], formatted: String? = nil, forNoteURL noteURL: URL? = nil) {
        // Solo actualizar si hay sugerencias nuevas válidas
        guard !newSuggestions.isEmpty else { 
            clearSuggestions()
            return 
        }
        
        // Si se proporciona URL, guardar en caché inmediatamente
        if let noteURL = noteURL, let formatted = formatted {
            self.currentNoteURL = noteURL
            self.currentFormattedText = formatted
            saveSuggestions(formatted: formatted, suggestions: newSuggestions, forNoteURL: noteURL)
            
            // Forzar guardado en UserDefaults inmediatamente
            saveAllSuggestions()
            print("Sugerencias guardadas para: \(noteURL.lastPathComponent)")
        }
        
        // Primero ocultar por completo para forzar recarga de la vista
        isVisible = false
        isAnimating = false
        
        // Pequeña pausa para asegurar reinicio completo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Actualizar sugerencias
            self.suggestions = newSuggestions
            self.isAnimating = true
            
            // Mostrar con animación
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isVisible = true
            }
            
            // Marcar que la animación ha terminado después de un tiempo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.isAnimating = self?.isVisible ?? false
            }
        }
    }
    
    /// Oculta la vista de sugerencias sin borrar las sugerencias
    func hideSuggestions() {
        isAnimating = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = false
        }
        
        // Marcar que la animación ha terminado después de un tiempo
        // pero NO limpiar las sugerencias para que estén disponibles si se vuelve a abrir
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isAnimating = self?.isVisible ?? false
            // No limpiamos suggestions aquí para mantenerlas en memoria
        }
    }
    
    /// Limpia las sugerencias actualmente mostradas (no borra de la base de datos)
    func clearSuggestions() {
        isAnimating = true
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            isVisible = false
        }
        
        // Retrasamos la limpieza de las sugerencias para que no desaparezcan
        // mientras se está animando la desaparición de la vista
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.suggestions = []
            self?.isAnimating = false
        }
    }
    
    // MARK: - Persistencia de sugerencias
    
    /// Guarda sugerencias para una nota específica
    func saveSuggestions(formatted: String, suggestions: [String], forNoteURL noteURL: URL, textModified: Bool = false) {
        let noteSuggestions = NoteSuggestions(formatted: formatted, suggestions: suggestions, textModified: textModified)
        let key = noteURL.path
        noteSuggestionsCache[key] = noteSuggestions
    }
    
    /// Marca las sugerencias de una nota como "texto modificado"
    func markSuggestionsAsTextModified(forNoteURL noteURL: URL) {
        let key = noteURL.path
        if let cached = noteSuggestionsCache[key] {
            // Crear una nueva instancia con el campo textModified actualizado
            let updatedSuggestions = NoteSuggestions(
                formatted: cached.formatted,
                suggestions: cached.suggestions,
                textModified: true
            )
            noteSuggestionsCache[key] = updatedSuggestions
            
            // Guardar los cambios inmediatamente
            saveAllSuggestions()
        }
    }
    
    /// Carga sugerencias para una nota específica
    /// - Returns: Texto formateado, sugerencias y estado de modificación si existen, nil en caso contrario
    func loadSuggestions(forNoteURL noteURL: URL) -> (formatted: String, suggestions: [String], textModified: Bool?)? {
        let key = noteURL.path
        if let cached = noteSuggestionsCache[key] {
            print("Sugerencias cargadas para: \(noteURL.lastPathComponent)")
            return (cached.formatted, cached.suggestions, cached.textModified)
        }
        return nil
    }
    
    /// Comprueba si hay sugerencias guardadas para una nota
    func hasSavedSuggestions(forNoteURL noteURL: URL) -> Bool {
        let key = noteURL.path
        let result = noteSuggestionsCache[key] != nil
        print("¿Tiene sugerencias guardadas \(noteURL.lastPathComponent)?: \(result)")
        return result
    }
    
    /// Muestra sugerencias guardadas para una nota específica
    func showSavedSuggestions(forNoteURL noteURL: URL) -> Bool {
        self.currentNoteURL = noteURL
        if let cached = loadSuggestions(forNoteURL: noteURL) {
            print("Mostrando sugerencias guardadas: \(cached.suggestions)")
            self.currentFormattedText = cached.formatted
            setSuggestions(cached.suggestions)
            return true
        }
        return false
    }
    
    /// Borra las sugerencias guardadas para una nota específica
    func deleteSavedSuggestions(forNoteURL noteURL: URL) {
        let key = noteURL.path
        noteSuggestionsCache.removeValue(forKey: key)
        saveAllSuggestions()
    }
    
    /// Guarda todas las sugerencias en UserDefaults
    func saveAllSuggestions() {
        do {
            let data = try JSONEncoder().encode(noteSuggestionsCache)
            UserDefaults.standard.set(data, forKey: suggestionsStorageKey)
            print("Todas las sugerencias guardadas correctamente. Total: \(noteSuggestionsCache.count)")
        } catch {
            print("Error al guardar sugerencias: \(error.localizedDescription)")
        }
    }
    
    /// Carga todas las sugerencias guardadas desde UserDefaults
    private func loadAllSavedSuggestions() {
        guard let data = UserDefaults.standard.data(forKey: suggestionsStorageKey) else { 
            print("No hay sugerencias guardadas previamente")
            return 
        }
        
        do {
            let decoded = try JSONDecoder().decode([String: NoteSuggestions].self, from: data)
            noteSuggestionsCache = decoded
            print("Sugerencias cargadas. Total: \(decoded.count)")
        } catch {
            print("Error al cargar sugerencias: \(error.localizedDescription)")
        }
    }
} 