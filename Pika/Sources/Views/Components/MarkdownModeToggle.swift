import SwiftUI

/// Toggle minimalista con dos botones planos para alternar entre RAW y BEAUTY
struct MarkdownModeToggle: View {
    @Binding var isRaw: Bool
    
    // Configuración visual
    private let iconSpacing: CGFloat = 0 // Distancia reducida entre los iconos
    private let iconSize: CGFloat = 15 // Tamaño para los iconos
    
    var body: some View {
        // Dos botones minimalistas con separador entre ellos
        HStack(spacing: iconSpacing) {
            // Botón RAW (<>)
            Button {
                if !isRaw {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isRaw = true
                    }
                }
            } label: {
                Text("<>")
                    .font(.system(size: iconSize, weight: .medium, design: .monospaced))
                    .foregroundColor(isRaw ? .white : Color(UIColor.lightGray))
            }
            .accessibilityLabel("Editar Markdown")
            
            // Separador
            Text("/")
                .font(.system(size: iconSize-2, weight: .light))
                .foregroundColor(Color(UIColor.lightGray))
                .padding(.horizontal, 1)
            
            // Botón BEAUTY (Aa)
            Button {
                if isRaw {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isRaw = false
                    }
                }
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(!isRaw ? .white : Color(UIColor.lightGray))
            }
            .accessibilityLabel("Vista Formateada")
        }
    }
}

struct MarkdownModeToggle_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Fondo negro para simular dark mode
            
            VStack(spacing: 40) {
                MarkdownModeToggle(isRaw: .constant(true))
                MarkdownModeToggle(isRaw: .constant(false))
            }
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 