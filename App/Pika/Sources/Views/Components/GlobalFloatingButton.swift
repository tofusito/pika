import SwiftUI

/// Botón flotante global que cambia de apariencia y comportamiento según el contexto
struct GlobalFloatingButton: View {
    @StateObject private var store = FloatingButtonStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatePulse: Bool = false
    
    var body: some View {
        Button(action: {
            store.executeAction()
        }) {
            Group {
                switch store.currentAction {
                case .addNote:
                    // Botón de añadir nota
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                
                case .transformNote:
                    // Botón de transformar texto
                    if store.isLoading {
                        // Icono rotativo durante la carga
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 30))
                            .rotationEffect(Angle(degrees: animatePulse ? 360 : 0))
                            .onAppear {
                                withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                                    animatePulse = true
                                }
                            }
                    } else {
                        // Icono normal para transformación
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 24))
                    }
                    
                case .showSuggestions:
                    // Icono cuando hay sugerencias guardadas
                    Image(systemName: "circle.badge.questionmark")
                        .font(.system(size: 24))
                    
                case .none:
                    // No debería mostrarse, pero por seguridad
                    EmptyView()
                }
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
        }
        .frame(width: 56, height: 56)
        .background(
            Circle().fill(colorScheme == .dark ? Color.white : Color.black)
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
        .padding(.trailing, 40)
        .padding(.bottom, 80)
        .opacity(store.isVisible ? 1 : 0)
        .scaleEffect(store.isVisible ? 1 : 0.5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.currentAction)
        .allowsHitTesting(store.isVisible)
    }
} 