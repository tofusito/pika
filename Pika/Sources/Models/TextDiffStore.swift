import Foundation
import SwiftUI
import Combine

/// Store for handling text differences and changes
class TextDiffStore: ObservableObject {
    /// Shared singleton
    static let shared = TextDiffStore()
    
    /// Original text before changes
    @Published var originalText: String = ""
    
    /// Modified text after changes
    @Published var modifiedText: String = ""
    
    /// Indicates if there are active differences to show
    @Published var hasDiff: Bool = false
    
    /// Lines that have been modified (0-based indices)
    @Published var modifiedLines: Set<Int> = []
    
    /// Private constructor for singleton
    private init() {}
    
    /// Starts a diff session with the original text
    func startDiff(original: String) {
        self.originalText = original
        self.modifiedText = original
        self.hasDiff = false
        self.modifiedLines = []
    }
    
    /// Updates the modified text and calculates differences
    func updateModifiedText(_ newText: String) {
        self.modifiedText = newText
        calculateDiff()
    }
    
    /// Accepts changes, setting the new text as original
    func acceptChanges() {
        self.originalText = self.modifiedText
        self.hasDiff = false
        self.modifiedLines = []
    }
    
    /// Rejects changes, returning to the original text
    func rejectChanges() -> String {
        self.modifiedText = self.originalText
        self.hasDiff = false
        self.modifiedLines = []
        return self.originalText
    }
    
    /// Calculates which lines have been modified with improved algorithm
    private func calculateDiff() {
        let originalLines = originalText.components(separatedBy: "\n")
        let modifiedLines = modifiedText.components(separatedBy: "\n")
        
        // Limpia el conjunto de líneas modificadas
        self.modifiedLines.removeAll()
        
        // Algoritmo de Myers para encontrar el LCS (Longest Common Subsequence)
        let diffResult = computeDiff(oldLines: originalLines, newLines: modifiedLines)
        
        // Marcamos las líneas modificadas basándonos en el resultado del diff
        for (_, change) in diffResult.enumerated() {
            switch change {
            case .insert(let lineIndex, _):
                // Línea insertada, marcarla
                self.modifiedLines.insert(lineIndex)
                
                // Añadir contexto - marcar una línea antes y después
                if lineIndex > 0 {
                    self.modifiedLines.insert(lineIndex - 1)
                }
                
                if lineIndex < modifiedLines.count - 1 {
                    self.modifiedLines.insert(lineIndex + 1)
                }
                
            case .delete(let lineIndex, _):
                // Línea eliminada, marcar línea actual o anterior
                if lineIndex < modifiedLines.count {
                    self.modifiedLines.insert(lineIndex)
                } else if modifiedLines.count > 0 {
                    self.modifiedLines.insert(modifiedLines.count - 1)
                }
                
            case .update(let lineIndex, _, _):
                // Línea modificada, marcarla
                self.modifiedLines.insert(lineIndex)
            }
        }
        
        // Si hay bloques de líneas modificadas consecutivas, asegurarse de incluir todo el bloque
        var additionalLines = Set<Int>()
        
        for line in modifiedLines.indices {
            // Si una línea está marcada como modificada
            if self.modifiedLines.contains(line) {
                // Verificar si hay bloques de texto con marcadores especiales
                if line < modifiedLines.count {
                    let currentLine = modifiedLines[line]
                    
                    // Buscar patrones de bloque markdown (como encabezados, listas, etc.)
                    if (currentLine.hasPrefix("##") || // Encabezados
                        currentLine.hasPrefix("-") ||  // Listas
                        currentLine.hasPrefix("*") ||  // Listas alternativas
                        currentLine.contains("wikipedia") || // Palabras clave específicas
                        currentLine.contains("Wikipedia")) {
                        
                        // Buscar hacia adelante hasta el final del bloque
                        var nextIndex = line + 1
                        while nextIndex < modifiedLines.count {
                            // Marcar hasta encontrar línea vacía, otro encabezado o final de archivo
                            if modifiedLines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty ||
                               modifiedLines[nextIndex].hasPrefix("##") {
                                break
                            }
                            additionalLines.insert(nextIndex)
                            nextIndex += 1
                        }
                    }
                }
            }
        }
        
        // Añadir las líneas adicionales detectadas
        for line in additionalLines {
            self.modifiedLines.insert(line)
        }
        
        // Tratar de detectar contenido específico como bloques Wikipedia
        var i = 0
        while i < modifiedLines.count {
            let line = i < modifiedLines.count ? modifiedLines[i] : ""
            if line.contains("Wikipedia") || line.contains("wikipedia") {
                // Encontramos un patrón de Wikipedia - buscar por rango completo
                
                // Buscar atrás para encontrar encabezados o inicio del bloque
                var startIndex = i
                while startIndex > 0 {
                    let prevLine = modifiedLines[startIndex - 1]
                    if prevLine.hasPrefix("##") || prevLine.isEmpty {
                        break
                    }
                    startIndex -= 1
                }
                
                // Añadir todas las líneas desde el encabezado
                for index in startIndex...i {
                    self.modifiedLines.insert(index)
                }
                
                // Buscar hacia adelante para encontrar todas las líneas relacionadas
                var endIndex = i
                while endIndex < modifiedLines.count - 1 {
                    let nextLine = modifiedLines[endIndex + 1]
                    if nextLine.hasPrefix("##") || nextLine.isEmpty {
                        break
                    }
                    if nextLine.contains("wikipedia") || 
                       nextLine.contains("Wikipedia") || 
                       nextLine.hasPrefix("-") || 
                       nextLine.hasPrefix("*") || 
                       nextLine.contains("http") {
                        endIndex += 1
                    } else {
                        break
                    }
                }
                
                // Añadir todas las líneas hasta el final del bloque
                for index in i...endIndex {
                    self.modifiedLines.insert(index)
                }
                
                // Saltar al final del bloque para continuar la búsqueda
                i = endIndex + 1
            } else {
                i += 1
            }
        }
        
        // Para textos muy diferentes, seguimos usando la lógica original
        if originalLines.count > 0 && modifiedLines.count > 0 {
            let totalDifferent = modifiedLines.filter { line in
                !originalLines.contains(line)
            }.count
            
            // Si más del 80% del contenido es diferente, considera todo el texto como modificado
            if (Double(totalDifferent) / Double(modifiedLines.count)) > 0.8 {
                for i in 0..<modifiedLines.count {
                    self.modifiedLines.insert(i)
                }
            }
        }
        
        // Actualiza el estado de diff
        self.hasDiff = !self.modifiedLines.isEmpty
    }
    
    /// Tipo de cambio en el algoritmo de diff
    private enum DiffChange {
        case insert(Int, String)    // Índice, contenido
        case delete(Int, String)    // Índice, contenido
        case update(Int, String, String)  // Índice, contenido original, contenido nuevo
    }
    
    /// Computa las diferencias entre dos arrays de líneas
    private func computeDiff(oldLines: [String], newLines: [String]) -> [DiffChange] {
        var changes = [DiffChange]()
        
        let oldCount = oldLines.count
        let newCount = newLines.count
        var i = 0
        var j = 0
        
        // Algoritmo simplificado para encontrar cambios
        while i < oldCount || j < newCount {
            // Líneas idénticas - avanzar ambos índices
            if i < oldCount && j < newCount && oldLines[i] == newLines[j] {
                i += 1
                j += 1
                continue
            }
            
            // Buscar el próximo punto de sincronización (líneas iguales)
            var nextI = i
            var nextJ = j
            var foundMatch = false
            
            // Buscar hacia adelante en ambos textos para encontrar la próxima coincidencia
            let searchLimit = 10 // Buscar hasta 10 líneas adelante para evitar búsquedas excesivas
            
            for oi in i..<min(i + searchLimit, oldCount) {
                for nj in j..<min(j + searchLimit, newCount) {
                    if oldLines[oi] == newLines[nj] {
                        nextI = oi
                        nextJ = nj
                        foundMatch = true
                        break
                    }
                }
                if foundMatch { break }
            }
            
            // Procesar los cambios hasta el próximo punto de sincronización
            
            // Registrar eliminaciones (líneas que están en el original pero no en el nuevo)
            while i < nextI {
                changes.append(.delete(j, oldLines[i]))
                i += 1
            }
            
            // Registrar inserciones (líneas que están en el nuevo pero no en el original)
            while j < nextJ {
                changes.append(.insert(j, newLines[j]))
                j += 1
            }
            
            // Si no encontramos coincidencia, avanzar al menos un índice para evitar un bucle infinito
            if !foundMatch {
                if i < oldCount {
                    changes.append(.delete(j, oldLines[i]))
                    i += 1
                }
                
                if j < newCount {
                    changes.append(.insert(j, newLines[j]))
                    j += 1
                }
            }
        }
        
        return changes
    }
} 