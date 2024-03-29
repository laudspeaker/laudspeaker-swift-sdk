//
//  LaudspeakerApi.swift
//  Laudspeaker
//
//

import Foundation

class LaudspeakerApi {
    public let config: LaudspeakerConfig

    // default is 60s but we do 10s
    private let defaultTimeout: TimeInterval = 10

    init(_ config: LaudspeakerConfig) {
        self.config = config
    }

    func sessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        config.httpAdditionalHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "\(laudspeakerSdkName)/\(laudspeakerVersion)",
        ]

        return config
    }

    private func getURL(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
        return request
    }

    func batch(events: [LaudspeakerEvent], completion: @escaping (LaudspeakerBatchUploadInfo) -> Void) {
        guard let url = URL(string: "batch", relativeTo: config.host) else {
            print("Malformed batch URL error.")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: nil))
        }

        let config = sessionConfig()
        var headers = config.httpAdditionalHeaders ?? [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        config.httpAdditionalHeaders = headers

        let request = getURL(url)

        let toSend: [String: Any] = [
            "api_key": self.config.apiKey,
            "batch": events.map { $0.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            print("Error parsing the batch body: \(error)")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            print("Error gzipping the batch body: \(error).")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                print("Error calling the batch API: \(String(describing: error)).")
                return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let errorMessage = "Error sending events to batch API: status: \(httpResponse.statusCode), body: \(String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]))."
                print(errorMessage)
            } else {
                print("Events sent successfully.")
            }

            return completion(LaudspeakerBatchUploadInfo(statusCode: httpResponse.statusCode, error: error))
        }.resume()
    }
    
    func emitOne(event: [LaudspeakerEvent], completion: @escaping (LaudspeakerBatchUploadInfo) -> Void) {
        // Change to "events" endpoint
        guard let url = URL(string: "events/batch", relativeTo: config.host) else {
            print("Malformed URL error.")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: nil))
        }

        let config = sessionConfig()
        //var headers = config.httpAdditionalHeaders ?? [:]
        var headers: [String: String] = [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        // Ensure Authorization and Content-Type are included in the headers
        headers["Authorization"] = "Api-Key " + self.config.apiKey
        headers["Content-Type"] = "application/json"
        config.httpAdditionalHeaders = headers

        // Prepare the URLRequest with the given URL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let additionalHeaders = config.httpAdditionalHeaders as? [String: String] {
            for (key, value) in additionalHeaders {
                headers[key] = value
            }
        }
        
        request.allHTTPHeaderFields = headers

        // Adjust the payload to exclude the API key and change "batch" to a relevant key for your event data
        let toSend: [String: Any] = [
            //"event": event.toJSON(),
            "batch": event.map { $0.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        var data: Data?
        do {
            data = try JSONSerialization.data(withJSONObject: toSend, options: [])
        } catch {
            print("Error parsing the event body: \(error)")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            print("Error gzipping the event body: \(error).")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                print("Error calling the events API: \(String(describing: error)).")
                return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let errorMessage = "Error sending event to the events API: status: \(httpResponse.statusCode), body: \(String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]))."
                print(errorMessage)
            } else {
                print("Event sent successfully.")
            }

            return completion(LaudspeakerBatchUploadInfo(statusCode: httpResponse.statusCode, error: error))
        }.resume()
    }


    /*
    func emitOne(event: LaudspeakerEvent, completion: @escaping (LaudspeakerBatchUploadInfo) -> Void) {
        guard let url = URL(string: "batch", relativeTo: config.host) else {
            print("Malformed batch URL error.")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: nil))
        }

        let config = sessionConfig()
        var headers = config.httpAdditionalHeaders ?? [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        config.httpAdditionalHeaders = headers

        let request = getURL(url)

        let toSend: [String: Any] = [
            "Api_Key": self.config.apiKey,
            "batch":  { event.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            print("Error parsing the batch body: \(error)")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            print("Error gzipping the batch body: \(error).")
            return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                print("Error calling the batch API: \(String(describing: error)).")
                return completion(LaudspeakerBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let errorMessage = "Error sending event to event API: status: \(httpResponse.statusCode), body: \(String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]))."
                print(errorMessage)
            } else {
                print("Event sent successfully.")
            }

            return completion(LaudspeakerBatchUploadInfo(statusCode: httpResponse.statusCode, error: error))
        }.resume()
    }
    */

    func decide(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        var urlComps = URLComponents()
        urlComps.path = "/decide"
        urlComps.queryItems = [URLQueryItem(name: "v", value: "3")]

        guard let url = urlComps.url(relativeTo: config.host) else {
            print("Malformed decide URL error.")
            return completion(nil, nil)
        }

        let config = sessionConfig()

        let request = getURL(url)

        let toSend: [String: Any] = [
            "api_key": self.config.apiKey,
            "distinct_id": distinctId,
            "$anon_distinct_id": anonymousId,
            "$groups": groups,
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            print("Error parsing the decide body: \(error)")
            return completion(nil, error)
        }

        URLSession(configuration: config).uploadTask(with: request, from: data!) { data, response, error in
            if error != nil {
                print("Error calling the decide API: \(String(describing: error))")
                return completion(nil, error)
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let errorMessage = "Error calling decide API: status: \(httpResponse.statusCode), body: \(String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]))."
                print(errorMessage)

                return completion(nil,
                                  InternalLaudspeakerError(description: errorMessage))
            } else {
                print("Decide called successfully.")
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]
                completion(jsonData, nil)
            } catch {
                print("Error parsing the decide response: \(error)")
                completion(nil, error)
            }
        }.resume()
    }
}
