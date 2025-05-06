import SwiftUI

/// View for editing and displaying a Markdown note



struct NoteDetailView: View {
    // Mutable URL to reflect renamings
    @State private var currentURL: URL
    let autoFocus: Bool
    // Callback to inform parent about URL changes
    let onRename: ((URL, URL) -> Void)?
    @State private var text: String = ""
    @State private var isRaw: Bool = false
    @State private var showMarkdownGuide: Bool = false
    @FocusState private var isEditorFocused: Bool
    @State private var hasAppeared: Bool = false
    @State private var showPlaceholder: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    // Variables para la pildorita de edición
    @State private var showEditPill: Bool = false
    @State private var editPillTimer: Timer? = nil
    
    // Variables para el gesto de deslizamiento interactivo
    @State private var offset: CGFloat = 0
    @State private var isDraggingBack: Bool = false
    
    // States for OpenAI
    @State private var isProcessingWithAI: Bool = false
    @State private var aiError: Error? = nil
    @State private var showAIError: Bool = false
    @StateObject private var suggestionStore = SuggestionStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatePulse: Bool = false
    
    // Referencia al store del botón flotante
    @EnvironmentObject private var floatingButtonStore: FloatingButtonStore
    
    // States for custom input
    @State private var showingCustomInput: Bool = false
    @State private var customInputText: String = ""
    
    // States for title editing
    @State private var showTitleEditor: Bool = false
    @State private var newTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool
    
    // States for text diff
    @StateObject private var diffStore = TextDiffStore.shared
    @State private var showDiffView: Bool = false
    
    // Variables adicionales para rastrear si el texto ha sido modificado desde la última transformación
    @State private var lastTransformedText: String = ""
    @State private var textModifiedSinceTransform: Bool = false
    
    // Variable para almacenar el texto antes de transformarlo (para deshacer)
    @State private var previousText: String = ""
    @State private var hasPreviousText: Bool = false
    @State private var showUndoButton: Bool = false
    
    // Get the current note title
    private var noteTitle: String {
        currentURL.deletingPathExtension().lastPathComponent
    }

    init(noteURL: URL, autoFocus: Bool, onRename: ((URL, URL) -> Void)? = nil) {
        self._currentURL = State(wrappedValue: noteURL)
        self.autoFocus = autoFocus
        self.onRename = onRename
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content that will scroll down
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Note title in H1 format
                    Text(noteTitle)
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            newTitle = noteTitle
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showTitleEditor.toggle()
                            }
                            if showTitleEditor {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isTitleFieldFocused = true
                                }
                            } else {
                                isTitleFieldFocused = false
                            }
                        }
                    
                    // Title edit bar that appears between navigation and content
                    if showTitleEditor {
                        HStack(spacing: 12) {
                            ZStack(alignment: .trailing) {
                                TextField("Set a new title", text: $newTitle)
                                    .font(.headline)
                                    .padding(8)
                                    .padding(.trailing, 30) // Espacio para el botón de limpiar
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(8)
                                    .focused($isTitleFieldFocused)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        saveNewTitle()
                                    }
                                
                                // Botón X dentro del campo de texto que ahora limpia el texto
                                Button(action: {
                                    newTitle = ""
                                    isTitleFieldFocused = true
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 20))
                                }
                                .padding(.trailing, 8)
                            }
                            
                            // Botón de checkmark para guardar
                            Button(action: saveNewTitle) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(UIColor.label))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Note content
                    Group {
                        if showDiffView {
                            // Diff view when there are changes to review
                            DiffTextView(
                                diffStore: diffStore,
                                text: diffStore.modifiedText,
                                isEditing: $isRaw,
                                onAccept: {
                                    // Accept changes - assign modified text to main text
                                    text = diffStore.modifiedText
                                    diffStore.acceptChanges()
                                    // Guardar texto original para poder deshacer
                                    previousText = diffStore.originalText
                                    hasPreviousText = true
                                    showUndoButton = true
                                    // Save text and hide diff view
                                    saveNote()
                                    withAnimation {
                                        showDiffView = false
                                    }
                                },
                                onReject: {
                                    // Reject changes - keep original text
                                    text = diffStore.originalText
                                    _ = diffStore.rejectChanges()
                                    // Asegurarse de que no hay texto anterior (ya que cancelamos cambios)
                                    hasPreviousText = false
                                    showUndoButton = false
                                    withAnimation {
                                        showDiffView = false
                                    }
                                }
                            )
                        } else if isRaw {
                            // Standard raw text editor
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $text)
                                    .font(.body)
                                    .padding()
                                    .focused($isEditorFocused)
                                    // Explicitly deactivate the editor
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            isEditorFocused = false
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        }
                                    }
                                    .opacity(text.isEmpty && !isEditorFocused ? 0.02 : 1) // Almost invisible when empty and unfocused
                                    .onChange(of: text, { oldValue, newValue in
                                        // If there's an active diff, update the modified text
                                        if diffStore.hasDiff {
                                            diffStore.updateModifiedText(newValue)
                                        }
                                    })
                                
                                if text.isEmpty && !isEditorFocused {
                                    // Show placeholder only when text is empty and editor is unfocused
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("# Title")
                                            .font(.title)
                                            .foregroundColor(.gray.opacity(0.5))
                                        Text("Write your ideas here.")
                                            .font(.body)
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                    .padding()
                                    .allowsHitTesting(false)
                                    .opacity(showPlaceholder ? 1 : 0) // Control placeholder opacity
                                    .animation(.easeIn(duration: 0.5), value: showPlaceholder) // Specific animation for placeholder
                                }
                            }
                            .contentShape(Rectangle()) // Define the entire area as interactive
                            .onTapGesture {
                                // Only activate focus when the user specifically taps
                                isEditorFocused = true
                            }
                        } else {
                            // Stylized Markdown view
                            ZStack(alignment: .bottom) {
                                ScrollView {
                                    if text.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("# Title")
                                                .font(.title)
                                                .foregroundColor(.gray.opacity(0.5))
                                            Text("Write your ideas here.")
                                                .font(.body)
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .opacity(showPlaceholder ? 1 : 0) // Control placeholder opacity here too
                                        .animation(.easeIn(duration: 0.5), value: showPlaceholder) // Same animation
                                    } else {
                                        MarkdownView(text: text)
                                            .padding()
                                    }
                                }
                                .environment(\.layoutDirection, .leftToRight)
                                .scrollIndicators(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    // Mostrar la pildorita al hacer doble tap
                                    withAnimation(.easeIn(duration: 0.3)) {
                                        showEditPill = true
                                    }
                                    
                                    // Cancelar el timer anterior si existe
                                    editPillTimer?.invalidate()
                                    
                                    // Programar que desaparezca en 3 segundos
                                    editPillTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            showEditPill = false
                                        }
                                    }
                                }
                                
                                // Pildorita de edición
                                if showEditPill {
                                    Button(action: {
                                        withAnimation {
                                            isRaw = true
                                            isEditorFocused = true
                                            showEditPill = false
                                        }
                                    }) {
                                        Text("Edit")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(colorScheme == .dark ? .black : .white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                                                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                                            )
                                    }
                                    .padding(.bottom, 20)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .opacity(hasAppeared ? 1 : 0)
                }
                .offset(y: hasAppeared ? 0 : 50) // Initial appearance animation
                .animation(.easeInOut(duration: 0.3), value: isRaw)
                .animation(.easeOut(duration: 0.3), value: hasAppeared)
            }
            
            // Suggestions view that appears from below
            SuggestionsView { suggestion in
                // Guardar el texto original para poder deshacer
                previousText = text
                hasPreviousText = true
                
                // Start a diff session to show changes
                diffStore.startDiff(original: text)
                
                // If the suggestion is a short text, it's a normal suggestion to add
                if suggestion.count < 150 && !suggestion.contains("#") {
                    // Add suggestion to text and update diff
                    let newText = text + "\n\n" + suggestion
                    diffStore.updateModifiedText(newText)
                } else {
                    // Replace all text with the updated version
                    diffStore.updateModifiedText(suggestion)
                }
                
                // Show diff view for user to accept or reject
                withAnimation {
                    showDiffView = true
                    suggestionStore.hideSuggestions()
                    // No activamos aún showUndoButton porque se está mostrando el diff,
                    // se activará cuando se acepten los cambios
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            
            // Custom input view
            if showingCustomInput {
                CustomInputView(
                    isShowing: $showingCustomInput,
                    inputText: $customInputText,
                    onCancel: {
                        // Cancel action
                        customInputText = ""
                    },
                    applySuggestion: { formattedText, newSuggestions, currentInputText in
                        // Guardar el texto original para poder deshacer
                        previousText = self.text
                        hasPreviousText = true
                        
                        // Start a diff session to show changes
                        diffStore.startDiff(original: self.text)
                        
                        // Update text and diff
                        diffStore.updateModifiedText(formattedText)
                        
                        // Update suggestions in store but don't show them automatically
                        if !newSuggestions.isEmpty {
                            // Save suggestions in store for future use, but don't show them
                            suggestionStore.currentFormattedText = formattedText
                            suggestionStore.suggestions = newSuggestions
                            
                            // Save to cache for persistence
                            suggestionStore.saveSuggestions(
                                formatted: formattedText, 
                                suggestions: newSuggestions, 
                                forNoteURL: currentURL,
                                textModified: false
                            )
                            
                            // Force save to UserDefaults immediately
                            suggestionStore.saveAllSuggestions()
                            
                            // Ensure suggestions are not visible
                            if suggestionStore.isVisible {
                                suggestionStore.hideSuggestions()
                            }
                        }
                        
                        // Show diff view for user to accept or reject
                        withAnimation {
                            showDiffView = true
                            // No activamos aún showUndoButton porque se está mostrando el diff,
                            // se activará cuando se acepten los cambios
                        }
                    },
                    allSuggestions: suggestionStore.suggestions,
                    currentText: text
                )
                .zIndex(300) // Higher than suggestions view to ensure it's above
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Hamburger button to go back to list
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                }
            }
            
            // Botón para deshacer cambios (solo visible cuando hay texto anterior)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: restorePreviousText) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .opacity(showUndoButton ? 1 : 0)
                .disabled(!showUndoButton)
            }
            
            // Toggle RAW/BEAUTY using reusable component
            ToolbarItem(placement: .navigationBarTrailing) {
                MarkdownModeToggle(isRaw: $isRaw)
            }
            
            // Overflow menu with options
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Markdown Guide") {
                        showMarkdownGuide = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.primary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .offset(x: offset) // Aplicar el desplazamiento horizontal según el gesto
        .scaleEffect(1.0 - (offset / UIScreen.main.bounds.width) * 0.1) // Reducir escala ligeramente durante el deslizamiento
        .opacity(1.0 - (offset / UIScreen.main.bounds.width) * 0.3) // Reducir opacidad gradualmente
        .gesture(
            DragGesture(minimumDistance: 15, coordinateSpace: .local)
                .onChanged { value in
                    // Solo procesamos gestos desde el borde izquierdo
                    if value.startLocation.x < 50 {
                        isDraggingBack = true
                        // Limitar el desplazamiento máximo al ancho de la pantalla
                        let dragWidth = min(value.translation.width, UIScreen.main.bounds.width)
                        // Solo permitir deslizamiento hacia la derecha (positivo)
                        offset = max(0, dragWidth)
                    }
                }
                .onEnded { value in
                    // Si el deslizamiento fue lo suficientemente largo o rápido
                    if (offset > UIScreen.main.bounds.width * 0.4) || 
                       (value.predictedEndTranslation.width > UIScreen.main.bounds.width * 0.5) {
                        // Completar el gesto y volver atrás
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset = UIScreen.main.bounds.width
                        }
                        // Pequeño retraso para que se vea la animación antes de dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            dismiss()
                        }
                    } else {
                        // Si no se completa el gesto, volver a la posición original
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            offset = 0
                            isDraggingBack = false
                        }
                    }
                }
        )
        .sheet(isPresented: $showMarkdownGuide) {
            MarkdownGuideView()
        }
        .alert("IA Error", isPresented: $showAIError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = aiError {
                Text(error.localizedDescription)
            }
        }
        .onAppear {
            loadNote()
            
            // Determinar initial mode:
            // If there's text, show BEAUTY, otherwise, show RAW
            if text.isEmpty || autoFocus {
                isRaw = true
                // Explicitly NO give focus
                isEditorFocused = false
                
                // Ensure keyboard is hidden
                DispatchQueue.main.async {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            } else {
                isRaw = false
            }
            
            // Animate full view appearance
            withAnimation(.easeOut(duration: 0.3)) {
                hasAppeared = true
            }
            
            // Delay placeholder appearance slightly for staggered effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    showPlaceholder = true
                }
            }
            
            // Check if there are saved suggestions, but DO NOT show them automatically
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.preloadSavedSuggestionsIfNeeded()
            }
            
            // Configurar el botón flotante para esta vista
            setupFloatingButton()
        }
        .onDisappear {
            // Hide suggestions when user exits view
            suggestionStore.clearSuggestions()
            
            // Cancelar el timer de la pildorita si existe
            editPillTimer?.invalidate()
            editPillTimer = nil
        }
        .onChange(of: text, { oldValue, newValue in
            // Save automatically only if there's no active diff
            if !diffStore.hasDiff {
                saveNote()
            }
            
            // Detecta si el usuario modificó el texto después de una transformación
            if !lastTransformedText.isEmpty && lastTransformedText != newValue {
                textModifiedSinceTransform = true
                
                // Guardar el estado de modificación junto con las sugerencias
                if suggestionStore.hasSavedSuggestions(forNoteURL: currentURL) {
                    // Actualizar el estado de modificación en las sugerencias guardadas
                    suggestionStore.markSuggestionsAsTextModified(forNoteURL: currentURL)
                }
                
                // Actualizar el estado del botón flotante
                updateFloatingButtonState()
            }
        })
        .onChange(of: suggestionStore.showCustomInputRequested, { oldValue, newValue in
            if newValue {
                // Show custom input view when requested
                showingCustomInput = true
                // Reset flag
                suggestionStore.showCustomInputRequested = false
            }
        })
    }
    
    // Configurar el botón flotante según el estado actual
    private func setupFloatingButton() {
        // Comprobar si hay sugerencias guardadas
        let hasSuggestions = suggestionStore.hasSavedSuggestions(forNoteURL: currentURL)
        
        // Configurar el botón para transformar notas
        floatingButtonStore.setupForTransformNote(
            noteURL: currentURL,
            transformCallback: transformTextWithAI,
            showSuggestionsCallback: showSavedSuggestions,
            hasSavedSuggestions: hasSuggestions,
            textModified: textModifiedSinceTransform
        )
    }
    
    // Actualizar el estado del botón cuando cambia el estado del texto o sugerencias
    private func updateFloatingButtonState() {
        let hasSuggestions = suggestionStore.hasSavedSuggestions(forNoteURL: currentURL)
        
        if hasSuggestions && !textModifiedSinceTransform {
            floatingButtonStore.currentAction = .showSuggestions
        } else {
            floatingButtonStore.currentAction = .transformNote
        }
        
        floatingButtonStore.textModifiedSinceTransform = textModifiedSinceTransform
        floatingButtonStore.hasSavedSuggestions = hasSuggestions
    }
    
    // Mostrar sugerencias guardadas
    private func showSavedSuggestions() {
        _ = suggestionStore.showSavedSuggestions(forNoteURL: currentURL)
    }
    
    /// Function to transform text using OpenAI
    private func transformTextWithAI() {
        guard !text.isEmpty else { return }
        
        // Guardar el texto actual antes de transformarlo
        previousText = text
        hasPreviousText = true
        
        // If there are already saved suggestions for this note and the suggestions aren't visible currently,
        // show them instead of calling the API
        if !suggestionStore.isVisible && suggestionStore.hasSavedSuggestions(forNoteURL: currentURL) && !textModifiedSinceTransform {
            _ = suggestionStore.showSavedSuggestions(forNoteURL: currentURL)
            return
        }
        
        // Start loading animation
        withAnimation {
            isProcessingWithAI = true
            showUndoButton = false // Ocultar botón mientras carga
            floatingButtonStore.setLoading(true) // Actualizar estado de carga del botón flotante
        }
        
        // Hide keyboard if visible
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Call OpenAI service asynchronously
        Task {
            do {
                let result = try await OpenAIService.shared.transformNoteText(text)
                
                // Update on main thread
                await MainActor.run {
                    withAnimation {
                        // Update text with formatted version
                        text = result.formatted
                        
                        // Guardar el texto transformado para detectar cambios posteriores
                        lastTransformedText = result.formatted
                        textModifiedSinceTransform = false
                        
                        // Save formatted text
                        saveNote()
                        
                        // Update currentFormattedText before showing suggestions
                        suggestionStore.currentFormattedText = result.formatted
                        
                        // Guardar sugerencias pero SIN mostrarlas
                        suggestionStore.saveSuggestions(
                            formatted: result.formatted,
                            suggestions: result.suggestions,
                            forNoteURL: currentURL,
                            textModified: false // Indicar que el texto no está modificado aún
                        )
                        
                        // Asegurarse de que las sugerencias NO se muestran
                        if suggestionStore.isVisible {
                            suggestionStore.hideSuggestions()
                        }
                        
                        // Actualizar las sugerencias en memoria sin mostrarlas
                        suggestionStore.suggestions = result.suggestions
                        suggestionStore.currentNoteURL = currentURL
                        
                        // Change to display mode if we're in raw mode
                        if isRaw {
                            isRaw = false
                        }
                        
                        // Complete
                        isProcessingWithAI = false
                        floatingButtonStore.setLoading(false)
                        
                        // Mostrar botón de deshacer
                        showUndoButton = true
                        
                        // Actualizar el estado del botón flotante
                        updateFloatingButtonState()
                    }
                }
            } catch {
                // Update on main thread
                await MainActor.run {
                    withAnimation {
                        isProcessingWithAI = false
                        floatingButtonStore.setLoading(false)
                        aiError = error
                        showAIError = true
                        showUndoButton = false
                    }
                }
            }
        }
    }

    // Nueva función para restaurar texto anterior
    private func restorePreviousText() {
        guard hasPreviousText else { return }
        
        // Animar el cambio
        withAnimation {
            text = previousText
            saveNote()
            
            // Actualizar el estado para mostrar el icono de transformar de nuevo
            textModifiedSinceTransform = true
            if suggestionStore.hasSavedSuggestions(forNoteURL: currentURL) {
                suggestionStore.markSuggestionsAsTextModified(forNoteURL: currentURL)
            }
            
            // Ocultar botón de deshacer después de usarlo
            showUndoButton = false
        }
    }

    // Check if there are saved suggestions and apply formatted text if needed,
    // but DO NOT show suggestions automatically
    private func preloadSavedSuggestionsIfNeeded() {
        // If there are saved suggestions for this URL, load formatted text if needed
        if suggestionStore.hasSavedSuggestions(forNoteURL: currentURL) {
            if let saved = suggestionStore.loadSuggestions(forNoteURL: currentURL) {
                // Update currentFormattedText in SuggestionStore
                suggestionStore.currentFormattedText = saved.formatted
                
                // Actualizar estado de modificación desde los datos guardados
                textModifiedSinceTransform = saved.textModified ?? false
                if !textModifiedSinceTransform {
                    lastTransformedText = saved.formatted
                }
                
                // Ensure suggestions are not visible, regardless of their previous state
                if suggestionStore.isVisible {
                    suggestionStore.hideSuggestions()
                }
                
                // Preload suggestions in memory but DO NOT show them
                // Avoid using setSuggestions that could show them
                suggestionStore.suggestions = saved.suggestions
                suggestionStore.currentNoteURL = currentURL
                
                // If current text is empty or very basic, apply saved format
                if text.isEmpty || !text.contains("#") {
                    text = saved.formatted
                    saveNote()
                }
            }
        }
    }

    // Load file content into note
    private func loadNote() {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: currentURL.path) {
                let data = try Data(contentsOf: currentURL)
                
                if let content = String(data: data, encoding: .utf8) {
                    text = content
                }
            }
        } catch {
            // Error handling is silent to avoid disrupting the user experience
        }
    }

    // Save current content to file
    private func saveNote() {
        do {
            let data = Data(text.utf8)
            // Create intermediate directories if needed
            let fileManager = FileManager.default
            let directoryURL = currentURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            try data.write(to: currentURL, options: .atomic)
        } catch {
            // Error handling is silent to avoid disrupting the user experience
        }
    }
    
    // Save new title by renaming file
    private func saveNewTitle() {
        guard !newTitle.isEmpty, newTitle != noteTitle else {
            withAnimation {
                showTitleEditor = false
            }
            return
        }
        
        // Clean title of invalid characters for filenames
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let cleanedTitle = newTitle
            .components(separatedBy: invalidChars)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Make sure the title is not empty after cleaning
        guard !cleanedTitle.isEmpty else {
            newTitle = noteTitle
            withAnimation {
                showTitleEditor = false
            }
            return
        }
        
        // Create the new file URL
        let fileManager = FileManager.default
        let directoryURL = currentURL.deletingLastPathComponent()
        let newFileName = "\(cleanedTitle).md"
        var newURL = directoryURL.appendingPathComponent(newFileName)
        
        // Check if a file with that name already exists
        if fileManager.fileExists(atPath: newURL.path) {
            // If it exists, add a number at the end to make it unique
            var counter = 1
            var uniqueNewURL = newURL
            
            // Try incrementing names until finding one available
            while fileManager.fileExists(atPath: uniqueNewURL.path) && counter < 100 {
                let uniqueFileName = "\(cleanedTitle) (\(counter)).md"
                uniqueNewURL = directoryURL.appendingPathComponent(uniqueFileName)
                counter += 1
            }
            
            // Use the found unique name
            newURL = uniqueNewURL
        }
        
        do {
            // Save changes and rename
            saveNote()
            let oldURL = currentURL
            try fileManager.moveItem(at: oldURL, to: newURL)

            // Update local state and notify
            currentURL = newURL
            onRename?(oldURL, newURL)

            // Close title editor
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showTitleEditor = false
            }
            isTitleFieldFocused = false
        } catch {
            // Error handling is silent to avoid disrupting user experience
        }
    }
}

/// Floating view for custom input
struct CustomInputView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isShowing: Bool
    @Binding var inputText: String
    @FocusState var isFocused: Bool
    @State private var isProcessing: Bool = false
    @State private var animatePulse: Bool = false
    @State private var opacity: Double = 0 // For animating appearance smoothly
    var onCancel: () -> Void
    var applySuggestion: (String, [String], String) -> Void
    var allSuggestions: [String]
    var currentText: String
    
    var body: some View {
        ZStack {
            // Semi-transparent but dark background
            Color.black
                .opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if !isProcessing {
                        withAnimation(.easeOut(duration: 0.3)) {
                            opacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isShowing = false
                            onCancel()
                        }
                    }
                }
            
            VStack(spacing: 20) {
                TextField("Type your idea", text: $inputText)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding()
                    .background(colorScheme == .dark ? Color.black.opacity(0.08) : Color(.systemGray))
                    .cornerRadius(8)
                    .focused($isFocused)
                    .disabled(isProcessing)
                
                if isProcessing {
                    // Loading animation
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 30))
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .rotationEffect(Angle(degrees: animatePulse ? 360 : 0))
                        .onAppear {
                            withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                                animatePulse = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    // Cancel and Send buttons with the same size
                    HStack(spacing: 10) {
                        Button("Cancel") {
                            withAnimation(.easeOut(duration: 0.3)) {
                                opacity = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isShowing = false
                                onCancel()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .cornerRadius(8)
                        
                        Button("Send") {
                            guard !inputText.isEmpty else { return }
                            
                            // Activate processing animation
                            isProcessing = true
                            
                            // Hide keyboard
                            isFocused = false
                            
                            // Process custom suggestion the same way as in SuggestionsView
                            // using OpenAIService.applySuggestion
                            Task {
                                do {
                                    // Call API to apply custom suggestion
                                    let result = try await OpenAIService.shared.applySuggestion(
                                        currentText: currentText,
                                        allSuggestions: allSuggestions,
                                        selectedSuggestion: inputText
                                    )
                                    
                                    // Update on main thread
                                    await MainActor.run {
                                        // Apply suggestion with processed results
                                        applySuggestion(result.formatted, result.suggestions, currentText)
                                        
                                        // Clear and close
                                        inputText = ""
                                        isProcessing = false
                                        
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            opacity = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isShowing = false
                                        }
                                    }
                                } catch {
                                    // In case of error, use basic form
                                    await MainActor.run {
                                        applySuggestion(inputText, allSuggestions, currentText)
                                        inputText = ""
                                        isProcessing = false
                                        
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            opacity = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isShowing = false
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .cornerRadius(8)
                        .disabled(inputText.isEmpty)
                        .opacity(inputText.isEmpty ? 0.5 : 1)
                    }
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color.white : Color.black)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .padding(.bottom, 200)
            .zIndex(200)
            .opacity(opacity)
        }
        .opacity(opacity)
        .onAppear {
            // Focus text field with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
            
            // Animate appearance smoothly
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
        }
    }
} 
