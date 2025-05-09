import Foundation
import Network

/// Expected output structure from the OpenAI API
struct NoteOutput: Codable {
    let formatted: String
    let suggestions: [String]
}

/// Specific errors for OpenAIService
enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case apiError(statusCode: Int, message: String)
    case malformedResponse
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI key is not configured. Go to Settings to save it."
        case .apiError(_, let message):
            return message
        case .malformedResponse:
            return "Malformed response from OpenAI."
        case .networkUnavailable:
            return "No internet connection."
        }
    }
}

/// Service to call OpenAI without external libraries
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

    /// Gets the API key from UserDefaults
    private func getApiKey() -> String? {
        UserDefaults.standard.string(forKey: "openaiApiKey")
    }
    
    /// Checks if the API key is configured
    var isApiKeyConfigured: Bool {
        getApiKey()?.isEmpty == false
    }

    /// Builds an ephemeral URLSession to avoid reusing HTTP/3 state in simulator
    private func createURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    /// Transforms raw text into formatted note and suggestions
    /// - Parameter rawText: Unstructured input text
    /// - Returns: NoteOutput with 'formatted' and 'suggestions'
    func transformNote(rawText: String) async throws -> NoteOutput {
        // 1. Verify network connectivity
        guard NetworkMonitor.shared.isConnected else {
            throw OpenAIServiceError.networkUnavailable
        }

        // 2. Check API key
        guard isApiKeyConfigured else {
            throw OpenAIServiceError.missingAPIKey
        }

        // 3. Build prompt and structured format
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

        In addition, provide up to **3 concise, context-aware suggestions** under the key \\"suggestions\\" that could help improve, extend, or deepen the note. In english. These should be brief (max 30 characters each) and relevant to the specific content, such as:
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

        // 4. Prepare request body with JSON Schema for strict output
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
            // Structured format instruction
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "note_output",
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        // 5. Configure URLRequest
        let url = URL(string: "https://api.openai.com/v1/responses")! // endpoint with "text.format" support
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(getApiKey()!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 5b. Disable HTTP/3 in simulator
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

        // 6. Send request with retries and backoff
        let session = createURLSession()
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

        // 7. Validate status code
        guard response.statusCode == 200 else {
            let errJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (errJSON?["error"] as? [String: Any])?["message"] as? String 
                ?? "Request failed with status \(response.statusCode)"
            throw OpenAIServiceError.apiError(statusCode: response.statusCode, message: msg)
        }

        // Print always only the suggestions
        if let raw = String(data: data, encoding: .utf8) {
            // Extract suggestions from JSON
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

        // 8. Extract `formatted` and `suggestions` from nested JSON
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

    /// Applies a selected suggestion to the note text and generates a new suggestion
    /// - Parameters:
    ///   - currentText: Current note text (already formatted)
    ///   - allSuggestions: List of all current suggestions
    ///   - selectedSuggestion: The suggestion selected by the user to apply
    /// - Returns: NoteOutput with updated formatted text and updated suggestions
    func applySuggestion(currentText: String, allSuggestions: [String], selectedSuggestion: String) async throws -> NoteOutput {
        // 1. Verify network connectivity
        guard NetworkMonitor.shared.isConnected else {
            throw OpenAIServiceError.networkUnavailable
        }

        // 2. Check API key
        guard isApiKeyConfigured else {
            throw OpenAIServiceError.missingAPIKey
        }

        // 3. Build prompt and structured format
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
        
        // Determine which suggestions were not selected
        let nonSelectedSuggestions = allSuggestions.filter { $0 != selectedSuggestion }
        
        // 4. Create user message with necessary information
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

        // 5. Prepare request body with JSON Schema for strict output
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
            // Structured format instruction
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "note_output",
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        // 6. Configure URLRequest
        let url = URL(string: "https://api.openai.com/v1/responses")! // endpoint with "text.format" support
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(getApiKey()!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 6b. Disable HTTP/3 in simulator
        #if targetEnvironment(simulator)
        request.assumesHTTP3Capable = false
        #endif
        
        #if DEBUG
        print("→ Applying suggestion: \(selectedSuggestion)")
        print("→ Non-selected suggestions to keep: \(nonSelectedSuggestions)")
        #endif

        // 7. Send request with retries and backoff
        let session = createURLSession()
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

        // 8. Validate status code
        guard response.statusCode == 200 else {
            let errJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (errJSON?["error"] as? [String: Any])?["message"] as? String 
                ?? "Request failed with status \(response.statusCode)"
            throw OpenAIServiceError.apiError(statusCode: response.statusCode, message: msg)
        }

        // 9. Extract `formatted` and `suggestions` from nested JSON
        let wrapper = try JSONDecoder().decode(APIWrapper.self, from: data)
        guard let contentText = wrapper.output.first?.content.first?.text,
              let innerData = contentText.data(using: .utf8),
              let innerJSON = try JSONSerialization.jsonObject(with: innerData) as? [String: Any],
              let formatted = innerJSON["formatted"] as? String,
              let suggestions = innerJSON["suggestions"] as? [String] else {
            throw OpenAIServiceError.malformedResponse
        }
        
        // Verify that non-selected suggestions are present
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
