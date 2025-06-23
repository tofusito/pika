import SwiftUI
import SwiftDown

struct SwiftDownView: View {
    let text: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        SwiftDownEditor(text: .constant(text))
            .isEditable(false)
            .insetsSize(16)
            .theme(colorScheme == .dark ? Theme.BuiltIn.defaultDark.theme() : Theme.BuiltIn.defaultLight.theme())
    }
}

#Preview {
    SwiftDownView(text: """
    # Título de ejemplo
    
    Este es un **texto** en *markdown* de ejemplo.
    
    - Item 1
    - Item 2
    
    ```swift
    let hello = "world"
    print(hello)
    ```
    """)
} 