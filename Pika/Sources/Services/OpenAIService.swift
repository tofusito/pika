import Foundation
import Network

/// Estructura de salida esperada desde la API de OpenAI
struct NoteOutput: Codable {
    let formatted: String
    let suggestions: [String]
}

/// Errores específicos de OpenAIService
enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case apiError(statusCode: Int, message: String)
    case malformedResponse
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "La clave de OpenAI no está configurada. Ve a Ajustes para guardarla."
        case .apiError(_, let message):
            return message
        case .malformedResponse:
            return "Respuesta mal formada desde OpenAI."
        case .networkUnavailable:
            return "No hay conexión a internet."
        }
    }
}

/// Servicio para llamar a OpenAI sin librerías externas
final class OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    // Internal wrapper to parse API response for suggestions
    private struct APIWrapper: Codable {
        struct Item: Codable {
            struct MessageContent: Codable {
                let type: String
                let annotations: [String]
                let text: String
            }
            let content: [MessageContent]
        }
        let output: [Item]
    }

    /// Obtiene la API key desde UserDefaults
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
    }
    /// Verifica si la API key está configurada
    private var isApiKeyConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Construye una sesión URLSession ephemeral para evitar reutilizar estado HTTP/3 en simulador
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    /// Transforma un texto crudo en nota formateada y sugerencias
    /// - Parameter rawText: Texto desordenado de entrada
    /// - Returns: NoteOutput con 'formatted' y 'suggestions'
    func transformNoteText(_ rawText: String) async throws -> NoteOutput {
        // 1. Verificar conectividad de red
        guard NetworkMonitor.shared.isConnected else {
            throw OpenAIServiceError.networkUnavailable
        }

        // 2. Comprobar API key
        guard isApiKeyConfigured else {
            throw OpenAIServiceError.missingAPIKey
        }

        // 3. Construir prompt y formato estructurado
        let systemInstructions = """
        You are a writing assistant for a note-taking app.

        Your task is to take any user-provided input — even if it's unstructured, disorganized, or poorly formatted — and return a clean, structured Markdown version of the content under the key \\"formatted\\".

        Use appropriate Markdown formatting to improve readability and presentation:
        - Use headings (e.g., #, ##, ###) for sections or titles.
        - Use bullet points or numbered lists for grouped content.
        - Use links where URLs or references are mentioned.
        - Use tables when comparing structured data.
        - Preserve existing formatting if it's correct and useful.

        Handle inputs defensively:
        - If the input is already well-formatted, return it unchanged under \\"formatted\\".
        - If only parts are well-formatted, keep them as-is and improve the rest.
        - If the input is blank, only return:
        {
            \\"formatted\\": \\"\\",
            \\"suggestions\\": []
        }
        - Do NOT hallucinate content; only reformat or enhance what is present.

        In addition, provide up to **3 concise, context-aware suggestions** under the key \\"suggestions\\" that could help improve, extend, or deepen the note. These should be brief (max 30 characters each) and relevant to the specific content, such as:
        - Add source or reference
        - Make a checklist
        - Create a comparison table
        - Include more detail

        Respond strictly in the following JSON format:

        {
        \\"formatted\\": \\"...\\",
        \\"suggestions\\": [\\"...\\", \\"...\\", \\"...\\"]
        }
        """

        // 4. Preparar el cuerpo de la petición con JSON Schema para salida estricta
        let modelName = "gpt-4.1-mini"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "formatted": ["type": "string"],
                "suggestions": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["formatted", "suggestions"],
            "additionalProperties": false
        ]

        let requestBody: [String: Any] = [
            "model": modelName,
            "input": [
                ["role": "system", "content": systemInstructions],
                ["role": "user",   "content": rawText]
            ],
            "temperature": 0.7,
            // Instrucción de formato estructurado
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "note_output",
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        // 5. Configurar URLRequest
        let url = URL(string: "https://api.openai.com/v1/responses")! // endpoint con soporte de "text.format"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 5b. Desactivar HTTP/3 en simulador
        #if targetEnvironment(simulator)
        request.assumesHTTP3Capable = false
        #endif

        // Debug prints
        #if DEBUG
        print("→ URL: \(request.url!)")
        print("→ Headers: \(request.allHTTPHeaderFields ?? [:])")
        if let body = request.httpBody, let str = String(data: body, encoding: .utf8) {
            print("→ Body JSON: \(str)")
        }
        #endif

        // 6. Enviar petición con reintentos y backoff
        let session = makeSession()
        var dataResponse: Data?
        var urlResponse: URLResponse?
        let retryCodes: Set<URLError.Code> = [.networkConnectionLost, .notConnectedToInternet, .timedOut]

        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                dataResponse = data
                urlResponse = response
                break
            } catch let err as URLError {
                if let underlying = err.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("Underlying error domain=\(underlying.domain), code=\(underlying.code)")
                }
                print("URLError code=\(err.code.rawValue) at attempt \(attempt)")
                if retryCodes.contains(err.code) && attempt < 3 {
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw OpenAIServiceError.apiError(statusCode: err.code.rawValue, message: err.localizedDescription)
            }
        }

        guard let data = dataResponse, let response = urlResponse as? HTTPURLResponse else {
            throw OpenAIServiceError.malformedResponse
        }

        // 7. Validar status code
        guard response.statusCode == 200 else {
            let errJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (errJSON?["error"] as? [String: Any])?["message"] as? String 
                ?? "Request failed with status \(response.statusCode)"
            throw OpenAIServiceError.apiError(statusCode: response.statusCode, message: msg)
        }

        // Imprimir siempre solo las suggestions
        if let raw = String(data: data, encoding: .utf8) {
            // Extraer suggestions del JSON
            if let wrapper = try? JSONDecoder().decode(APIWrapper.self, from: data),
               let contentText = wrapper.output.first?.content.first?.text,
               let innerData = contentText.data(using: .utf8),
               let innerJSON = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
               let suggestions = innerJSON["suggestions"] as? [String] {
                print("← Suggestions: \(suggestions)")
            } else {
                print("← RAW Response JSON: \(raw)")
            }
        } else {
            print("← RAW Response JSON: <non UTF8 data>")
        }

        // 8. Extraer `formatted` y `suggestions` desde el JSON anidado
        let wrapper = try JSONDecoder().decode(APIWrapper.self, from: data)
        guard let contentText = wrapper.output.first?.content.first?.text,
              let innerData = contentText.data(using: .utf8),
              let innerJSON = try JSONSerialization.jsonObject(with: innerData) as? [String: Any],
              let formatted = innerJSON["formatted"] as? String,
              let suggestions = innerJSON["suggestions"] as? [String] else {
            throw OpenAIServiceError.malformedResponse
        }
        let output = NoteOutput(formatted: formatted, suggestions: suggestions)
        #if DEBUG
        print("← Decoded NoteOutput: \(output)")
        #endif
        return output
    }

    /// Aplica una sugerencia seleccionada al texto de la nota y genera una nueva sugerencia
    /// - Parameters:
    ///   - currentText: Texto actual de la nota (ya formateado)
    ///   - allSuggestions: Lista de todas las sugerencias actuales
    ///   - selectedSuggestion: La sugerencia que el usuario ha seleccionado para aplicar
    /// - Returns: NoteOutput con texto formateado actualizado y sugerencias actualizadas
    func applySuggestion(currentText: String, allSuggestions: [String], selectedSuggestion: String) async throws -> NoteOutput {
        // 1. Verificar conectividad de red
        guard NetworkMonitor.shared.isConnected else {
            throw OpenAIServiceError.networkUnavailable
        }

        // 2. Comprobar API key
        guard isApiKeyConfigured else {
            throw OpenAIServiceError.missingAPIKey
        }

        // 3. Construir prompt y formato estructurado
        let systemInstructions = """
            You are a writing assistant for a note-taking app. 
            
            TASK:
            1. Apply the selected suggestion to the current note text
            2. Return the updated text in well-formatted Markdown under the key "formatted"
            3. Provide 3 suggestions under the key "suggestions" following these EXACT rules:
               - Keep the 2 original suggestions that were NOT selected (DO NOT modify them)
               - Add 1 NEW relevant suggestion that could further improve the note
               - Shorten the suggestions to a maximum of 30 characters each
            
            GUIDELINES:
            - Apply ONLY the selected suggestion, making appropriate changes to the text
            - Reformat the text to add the new content in an appropriate way
            - Format the result using clean Markdown with appropriate headings, lists, etc.
            - DO NOT modify the non-selected suggestions in any way - keep them exactly as provided
            - Ensure the new suggestion is distinct from all previous ones
            - Do NOT mention that changes were made or explain what you did
            
            Respond ONLY in JSON with this format:
            {
            "formatted": "...",
            "suggestions": ["...", "...", "..."]
            }
        """
        
        // Determinar cuáles son las sugerencias que no se seleccionaron
        let nonSelectedSuggestions = allSuggestions.filter { $0 != selectedSuggestion }
        
        // 4. Crear el mensaje del usuario con la información necesaria
        let userMessage = """
        CURRENT TEXT:
        \(currentText)
        
        SELECTED SUGGESTION TO APPLY:
        \(selectedSuggestion)
        
        NON-SELECTED SUGGESTIONS TO KEEP EXACTLY AS IS (DO NOT MODIFY THESE):
        \(nonSelectedSuggestions.enumerated().map { "[\($0 + 1)] \($1)" }.joined(separator: "\n"))
        
        INSTRUCTIONS:
        1. Apply the selected suggestion to the text
        2. Return the updated formatted text
        3. Include ALL non-selected suggestions in your response exactly as provided above
        4. Add ONE new suggestion that is different from all existing ones
        """

        // 5. Preparar el cuerpo de la petición con JSON Schema para salida estricta
        let modelName = "gpt-4.1-mini"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "formatted": ["type": "string"],
                "suggestions": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["formatted", "suggestions"],
            "additionalProperties": false
        ]

        let requestBody: [String: Any] = [
            "model": modelName,
            "input": [
                ["role": "system", "content": systemInstructions],
                ["role": "user",   "content": userMessage]
            ],
            "temperature": 0.7,
            // Instrucción de formato estructurado
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "note_output",
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        // 6. Configurar URLRequest
        let url = URL(string: "https://api.openai.com/v1/responses")! // endpoint con soporte de "text.format"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 6b. Desactivar HTTP/3 en simulador
        #if targetEnvironment(simulator)
        request.assumesHTTP3Capable = false
        #endif
        
        #if DEBUG
        print("→ Applying suggestion: \(selectedSuggestion)")
        print("→ Non-selected suggestions to keep: \(nonSelectedSuggestions)")
        #endif

        // 7. Enviar petición con reintentos y backoff
        let session = makeSession()
        var dataResponse: Data?
        var urlResponse: URLResponse?
        let retryCodes: Set<URLError.Code> = [.networkConnectionLost, .notConnectedToInternet, .timedOut]

        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                dataResponse = data
                urlResponse = response
                break
            } catch let err as URLError {
                if attempt < 3 && retryCodes.contains(err.code) {
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw OpenAIServiceError.apiError(statusCode: err.code.rawValue, message: err.localizedDescription)
            }
        }

        guard let data = dataResponse, let response = urlResponse as? HTTPURLResponse else {
            throw OpenAIServiceError.malformedResponse
        }

        // 8. Validar status code
        guard response.statusCode == 200 else {
            let errJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (errJSON?["error"] as? [String: Any])?["message"] as? String 
                ?? "Request failed with status \(response.statusCode)"
            throw OpenAIServiceError.apiError(statusCode: response.statusCode, message: msg)
        }

        // 9. Extraer `formatted` y `suggestions` desde el JSON anidado
        let wrapper = try JSONDecoder().decode(APIWrapper.self, from: data)
        guard let contentText = wrapper.output.first?.content.first?.text,
              let innerData = contentText.data(using: .utf8),
              let innerJSON = try JSONSerialization.jsonObject(with: innerData) as? [String: Any],
              let formatted = innerJSON["formatted"] as? String,
              let suggestions = innerJSON["suggestions"] as? [String] else {
            throw OpenAIServiceError.malformedResponse
        }
        
        // Verificar que las sugerencias no seleccionadas están presentes
        #if DEBUG
        let suggestionsSet = Set(suggestions)
        let nonSelectedSet = Set(nonSelectedSuggestions)
        let containsAllNonSelected = nonSelectedSet.isSubset(of: suggestionsSet)
        print("← Contains all non-selected suggestions: \(containsAllNonSelected)")
        #endif
        
        let output = NoteOutput(formatted: formatted, suggestions: suggestions)
        return output
    }
}
