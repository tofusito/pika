import SwiftUI

/// Modelo para la información de la aplicación
struct AppInfoContent {
    /// Nombre de la aplicación
    var appName: String = "Pika"
    
    /// Versión actual
    var version: String = "0.1"
    
    /// Icono utilizado en la parte superior (nombre del SF Symbol)
    var iconName: String = "doc.text.fill"
    
    /// Descripción breve de la app
    var description: String = "A simple note-taking app for capturing your ideas quickly and transforming them with AI."
    
    /// Nombre del desarrollador
    var developer: String = "Manuel J. Gutierrez"
    
    /// Año(s) del copyright
    var copyrightYear: String = "© 2025"
    
    /// URL de la política de privacidad (nil si no hay)
    var privacyPolicyURL: URL? = nil
    
    /// URL de los términos de uso (nil si no hay)
    var termsOfUseURL: URL? = nil
}

/// Vista de información de la aplicación
struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    /// Datos configurables de la información de la app
    var appInfo: AppInfoContent
    
    init(appInfo: AppInfoContent = AppInfoContent()) {
        self.appInfo = appInfo
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: appInfo.iconName)
                            .font(.system(size: 60))
                            .foregroundColor(.primary)
                            .padding(.top, 20)
                        
                        Text(appInfo.appName)
                            .font(.system(size: 28, weight: .bold))
                        
                        Text("Version \(appInfo.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(appInfo.description)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Developer")
                        Spacer()
                        Text(appInfo.developer)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Copyright")
                        Spacer()
                        Text(appInfo.copyrightYear)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Sección legal que solo aparece si hay URLs configuradas
                if appInfo.privacyPolicyURL != nil || appInfo.termsOfUseURL != nil {
                    Section(header: Text("Legal")) {
                        if let privacyURL = appInfo.privacyPolicyURL {
                            Button("Privacy Policy") {
                                openURL(privacyURL)
                            }
                        }
                        
                        if let termsURL = appInfo.termsOfUseURL {
                            Button("Terms of Use") {
                                openURL(termsURL)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    // Ejemplo con todas las opciones personalizadas
    let customInfo = AppInfoContent(
        appName: "Mi Aplicación",
        version: "2.1",
        iconName: "star.fill",
        description: "Esta es una descripción personalizada de la aplicación de ejemplo.",
        developer: "Desarrollador XYZ",
        copyrightYear: "© 2022-2023",
        privacyPolicyURL: URL(string: "https://example.com/privacy"),
        termsOfUseURL: URL(string: "https://example.com/terms")
    )
    
    return AppInfoView(appInfo: customInfo)
}

// Ejemplo de preview con los valores por defecto
#Preview("Default") {
    AppInfoView()
} 
