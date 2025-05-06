import SwiftUI

/// Vista para mostrar el texto con indicadores de líneas modificadas
struct DiffTextView: View {
    @ObservedObject var diffStore: TextDiffStore
    let text: String
    @Binding var isEditing: Bool
    var onAccept: () -> Void
    var onReject: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Editor o visualizador de texto
            ZStack(alignment: .topLeading) {
                if isEditing {
                    // Editor de texto sin scrollview para permitir control de líneas
                    TextEditor(text: Binding(
                        get: { text },
                        set: { diffStore.updateModifiedText($0) }
                    ))
                    .font(.body)
                    .padding()
                } else {
                    // Visor de texto con scroll
                    ScrollView {
                        Text(text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
                
                // Indicadores de líneas modificadas solo si hay diff
                if diffStore.hasDiff {
                    GeometryReader { geometry in
                        ForEach(Array(diffStore.modifiedLines), id: \.self) { lineIndex in
                            if let lineRect = getLineRect(forLineIndex: lineIndex, in: geometry) {
                                // Indicador de línea modificada
                                Rectangle()
                                    .fill(Color.white) // Siempre blanco independientemente del modo
                                    .frame(width: 4)
                                    .frame(height: lineRect.height)
                                    .position(x: 3, y: lineRect.midY)
                            }
                        }
                    }
                }
            }
            
            // Botones de aceptar/rechazar solo si hay diff
            if diffStore.hasDiff {
                VStack {
                    // Botones flotantes a la derecha
                    VStack(spacing: 10) {
                        // Botón para aceptar los cambios
                        Button(action: onAccept) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(8)
                        
                        // Botón para rechazar los cambios
                        Button(action: onReject) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(8)
                    }
                    .padding(.trailing, 12)
                    
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
    }
    
    /// Calcula la posición de una línea de texto en el editor
    /// - Parameters:
    ///   - lineIndex: Índice de la línea (base 0)
    ///   - geometry: Geometría del contenedor
    /// - Returns: Rectángulo que representa la posición de la línea
    private func getLineRect(forLineIndex lineIndex: Int, in geometry: GeometryProxy) -> CGRect? {
        // Divide el texto en líneas
        let lines = text.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return nil }
        
        // Altura aproximada por línea basada en el tamaño de fuente y el espacio de línea
        let fontSize: CGFloat = 17 // Tamaño aproximado de la fuente body
        let lineSpacing: CGFloat = 5 // Espacio adicional entre líneas
        let lineHeight: CGFloat = fontSize + lineSpacing
        
        // Calcular el espacio de padding superior para alinearlo mejor
        let topPadding: CGFloat = 16 // Padding estándar para los elementos de texto
        
        // Posición Y de la línea, considerando el padding
        let yPosition = topPadding + (CGFloat(lineIndex) * lineHeight)
        
        // Crear el rectángulo para la línea
        return CGRect(
            x: 0,
            y: yPosition,
            width: geometry.size.width,
            height: lineHeight
        )
    }
} 