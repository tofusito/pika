import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @State private var isApiKeyVisible = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .toggleStyle(SwitchToggleStyle(tint: isDarkMode ? Color.white.opacity(0.8) : Color.black.opacity(0.8)))
                }
                .listRowBackground(isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                .foregroundColor(isDarkMode ? .white : .black)
                
                Section(header: Text("API Integration")) {
                    HStack {
                        if isApiKeyVisible {
                            TextField("OpenAI API Key", text: $openaiApiKey)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("OpenAI API Key", text: $openaiApiKey)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                        }
                        
                        Button(action: {
                            isApiKeyVisible.toggle()
                        }) {
                            Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text("Necesaria para funciones avanzadas de IA.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                .foregroundColor(isDarkMode ? .white : .black)
            }
            .scrollContentBackground(.hidden)
            // En dark mode, usar gris oscuro de sistema como fondo del menú
            .background(isDarkMode ? Color(.systemGray6) : Color.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(isDarkMode ? .white : .black)
                }
            }
        }
        // Fondo total de la pantalla
        .background((isDarkMode ? Color.black : Color.white).ignoresSafeArea())
        // Forzar color scheme y acento minimalista
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .tint(.primary)
    }
} 