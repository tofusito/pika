import SwiftUI

/// Vista de sugerencias que aparece desde abajo ocupando todo el ancho
struct SuggestionsView: View {
    @StateObject private var store = SuggestionStore.shared
    @Environment(\.colorScheme) private var colorScheme
    var onSelectSuggestion: (String) -> Void
    
    // Estado para controlar cuando estamos aplicando una sugerencia con la API
    @State private var isApplyingSuggestion = false
    @State private var suggestionInProgress: String? = nil
    
    // Color de fondo de la vista principal, como en SettingsView
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6)
    }
    
    // Color de fondo para las tarjetas de sugerencias
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    // Color del texto de las sugerencias
    private var textColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        // Solo se muestra cuando hay sugerencias activas
        if store.isVisible || store.isAnimating {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Fondo semitransparente para permitir toques fuera
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            store.hideSuggestions()
                        }
                    
                    // Panel de sugerencias
                    VStack(spacing: 0) {
                        // Indicador de arrastre (pill)
                        Capsule()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                        
                        // Barra superior con título y botón de cierre
                        HStack {
                            Spacer()
                            
                            Text("Suggestions")
                                .font(.headline)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Spacer()
                            
                            Button(action: {
                                store.hideSuggestions()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 24))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        
                        // Línea divisoria
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                        
                        // Sugerencias como una lista vertical fija
                        VStack(spacing: 16) {
                            ForEach(store.suggestions, id: \.self) { suggestion in
                                SuggestionCard(
                                    suggestion: suggestion,
                                    backgroundColor: cardBackgroundColor,
                                    textColor: textColor,
                                    isLoading: isApplyingSuggestion && suggestionInProgress == suggestion
                                ) {
                                    // Al pulsar una sugerencia, la aplicamos usando la función de OpenAI
                                    applySuggestion(suggestion)
                                }
                            }
                            
                            // Botón "Other..."
                            SuggestionCard(
                                suggestion: "Other...",
                                backgroundColor: cardBackgroundColor,
                                textColor: textColor,
                                isLoading: false
                            ) {
                                store.hideSuggestions() // Ocultar primero
                                // Después de un pequeño retraso para asegurar que la animación de ocultar ha comenzado
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    store.showCustomInputRequested = true // Indicar que se debe mostrar la vista de entrada personalizada
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        
                        // Espaciador para asegurar que hay suficiente espacio inferior
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom : 20)
                    }
                    .background(
                        Rectangle()
                            .fill(backgroundColor)
                            .cornerRadius(15, corners: [.topLeft, .topRight])
                            .edgesIgnoringSafeArea(.bottom)
                    )
                    .offset(y: store.isVisible ? 0 : geometry.size.height)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.isVisible)
                .edgesIgnoringSafeArea(.all)
            }
            .transition(.opacity)
            .zIndex(100) // Asegurar que esté por encima de todo
            .overlay {
                // Ya no mostramos la vista personalizada aquí
            }
        }
    }
    
    /// Applies the selected suggestion using the API
    private func applySuggestion(_ suggestion: String) {
        guard !isApplyingSuggestion, 
              let noteURL = store.currentNoteURL, 
              let currentText = store.currentFormattedText else {
            // If we don't have the necessary data, apply the suggestion in a simple way
            onSelectSuggestion(suggestion)
            store.hideSuggestions()
            return
        }
        
        // Mark this suggestion as in progress
        isApplyingSuggestion = true
        suggestionInProgress = suggestion
        
        // Get current suggestions
        let allSuggestions = store.suggestions
        
        // Call API to apply the suggestion
        Task {
            do {
                let result = try await OpenAIService.shared.applySuggestion(
                    currentText: currentText,
                    allSuggestions: allSuggestions,
                    selectedSuggestion: suggestion
                )
                
                // Update on main thread
                await MainActor.run {
                    // Save new suggestions in memory so they're available
                    // when pressing the floating button again
                    store.suggestions = result.suggestions
                    store.currentFormattedText = result.formatted
                    
                    // Save to cache for persistence
                    store.saveSuggestions(
                        formatted: result.formatted, 
                        suggestions: result.suggestions, 
                        forNoteURL: noteURL,
                        textModified: false
                    )
                    
                    // Force save to UserDefaults immediately
                    store.saveAllSuggestions()
                    
                    // Inform the parent to update the note with updated text
                    onSelectSuggestion(result.formatted)
                    
                    // Hide suggestions after applying the selected one
                    // but DO NOT clear the suggestions array in memory
                    store.hideSuggestions()
                    
                    // Complete
                    isApplyingSuggestion = false
                    suggestionInProgress = nil
                }
            } catch {
                print("Error applying suggestion: \(error.localizedDescription)")
                
                // Update on main thread
                await MainActor.run {
                    // If there's an error, apply the suggestion in a simple way
                    onSelectSuggestion(suggestion)
                    store.hideSuggestions()
                    
                    isApplyingSuggestion = false
                    suggestionInProgress = nil
                }
            }
        }
    }
}

/// Individual card for each suggestion
struct SuggestionCard: View {
    let suggestion: String
    let backgroundColor: Color
    let textColor: Color
    let isLoading: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatePulse: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                Text(suggestion)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .font(.system(.body))
                    .foregroundColor(textColor)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                
                Spacer()
                
                if isLoading {
                    // Pulsing dot as loading indicator
                    Circle()
                        .fill(textColor)
                        .frame(width: 16, height: 16)
                        .scaleEffect(animatePulse ? 1.2 : 0.8)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                                animatePulse = true
                            }
                        }
                } else {
                    // Normal icon
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .font(.system(size: 22))
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                                .frame(width: 30, height: 30)
                        )
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
    }
}

// Extensión para aplicar esquinas redondeadas específicas
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Forma personalizada para esquinas redondeadas específicas
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Vistas previas
#Preview("Light Mode") {
    ZStack {
        Color.white.edgesIgnoringSafeArea(.all)
        
        SuggestionsView { suggestion in
            print("Selected: \(suggestion)")
        }
    }
    .preferredColorScheme(.light)
    .onAppear {
        // Simular sugerencias para previsualización
        SuggestionStore.shared.setSuggestions([
            "Agregar ejemplos para cada punto importante.",
            "Incluir referencias o enlaces relacionados.",
            "Añadir una conclusión al final de la sección."
        ])
    }
}

#Preview("Dark Mode") {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)
        
        SuggestionsView { suggestion in
            print("Selected: \(suggestion)")
        }
    }
    .preferredColorScheme(.dark)
    .onAppear {
        // Simular sugerencias para previsualización
        SuggestionStore.shared.setSuggestions([
            "Agregar ejemplos para cada punto importante.",
            "Incluir referencias o enlaces relacionados.",
            "Añadir una conclusión al final de la sección."
        ])
    }
} 