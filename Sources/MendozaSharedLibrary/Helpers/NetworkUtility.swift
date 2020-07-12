//
//  NetworkUtility.swift
//  MendozaSharedLibrary
//
//  Created by Ashraf Ali on 10/07/2020.
//

import Foundation

public struct Network {
    public init() {}
    
    public func request(url: String, method: String, headers: [(key: String, value: String)]? = nil, requestData: Data? = nil) {
        // Prepare URL
        guard let requestUrl = URL(string: url) else {
            fatalError("Incorrect URL")
        }

        // Prepare URL Request Object
        var request = URLRequest(url: requestUrl)
        request.httpMethod = method

        // Set HTTP Request Body
        if let requestBody = requestData {
            request.httpBody = requestBody
        }

        if let headers = headers {
            headers.forEach {
                request.addValue($0.value, forHTTPHeaderField: $0.value)
            }
        }

        // Perform HTTP Request
        let task = URLSession.shared.dataTask(with: request) { data, _, error in

            // Check for Error
            if let error = error {
                print("Error took place \(error)")
                return
            }

            // Convert HTTP Response Data to a String
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                print("Response data string:\n \(dataString)")
            }
        }
        task.resume()
    }
}

extension URLSession {
    public func performSynchronous(request: URLRequest) -> (data: Data?, response: URLResponse?, error: Error?) {
        let semaphore = DispatchSemaphore(value: 0)

        var data: Data?
        var response: URLResponse?
        var error: Error?

        let task = dataTask(with: request) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }

        task.resume()
        semaphore.wait()

        return (data, response, error)
    }
}
