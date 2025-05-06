//
//  PikaApp.swift
//  Pika
//
//  Created by Manuel Jesús Gutiérrez Fernández on 27/4/25.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct PikaApp: App {
    init() {
        // Iniciar NetworkMonitor para vigilar la red desde el inicio
        _ = NetworkMonitor.shared
        // Inicializar el store del botón flotante
        _ = FloatingButtonStore.shared
        // Configurar la carpeta Pika para ser visible en la app Archivos
        setupPikaFolderForFileApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(SuggestionStore.shared)
                    .environmentObject(FloatingButtonStore.shared)
                
                // Botón flotante global superpuesto a todas las vistas
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GlobalFloatingButton()
                    }
                }
                .ignoresSafeArea(.all)
            }
        }
    }
    
    // Configura la carpeta Pika para que sea visible en la app Archivos
    private func setupPikaFolderForFileApp() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var pikaFolderURL = documents.appendingPathComponent("Pikas", isDirectory: true)
        
        // Crear el directorio si no existe
        if !fileManager.fileExists(atPath: pikaFolderURL.path) {
            try? fileManager.createDirectory(at: pikaFolderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Activar la opción para que sea visible en la app Archivos
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        
        try? pikaFolderURL.setResourceValues(resourceValues)
        
        print("Pikas folder configured at: \(pikaFolderURL.path)")
    }
}
