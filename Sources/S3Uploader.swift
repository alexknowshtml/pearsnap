import Foundation
import CommonCrypto

class S3Uploader {
    static let shared = S3Uploader()
    
    private init() {}
    
    func upload(data: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let config = ConfigManager.shared.config else {
            completion(.failure(UploadError.noConfig))
            return
        }
        
        let filename = generateFilename()
        let contentType = "image/png"
        
        // Build the request
        guard let url = URL(string: "https://\(config.s3Bucket).\(config.s3Endpoint)/\(filename)") else {
            completion(.failure(UploadError.invalidURL))
            return
        }
        
        print("[S3] Uploading to: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("public-read", forHTTPHeaderField: "x-amz-acl")
        
        // Sign the request with AWS Signature V4
        signRequest(&request, config: config, payload: data)
        
        let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
            if let error = error {
                print("[S3] Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(UploadError.invalidResponse))
                return
            }
            
            print("[S3] Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let publicURL = "\(config.publicURLBase)/\(filename)"
                print("[S3] Success: \(publicURL)")
                completion(.success(publicURL))
            } else {
                // Log the error response body
                if let responseData = responseData, let body = String(data: responseData, encoding: .utf8) {
                    print("[S3] Error response: \(body)")
                }
                completion(.failure(UploadError.uploadFailed(httpResponse.statusCode)))
            }
        }
        task.resume()
    }
    
    private func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: Date())
        let random = String(format: "%04x", arc4random_uniform(65536))
        return "screenshots/\(timestamp)-\(random).png"
    }
    
    private func signRequest(_ request: inout URLRequest, config: S3Config, payload: Data) {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)
        
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)
        
        let host = "\(config.s3Bucket).\(config.s3Endpoint)"
        let path = request.url?.path ?? "/"
        
        let payloadHash = sha256Hash(data: payload)
        
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        
        // Create canonical request
        let signedHeaders = "content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = """
            content-type:\(request.value(forHTTPHeaderField: "Content-Type") ?? "")
            host:\(host)
            x-amz-acl:\(request.value(forHTTPHeaderField: "x-amz-acl") ?? "")
            x-amz-content-sha256:\(payloadHash)
            x-amz-date:\(amzDate)
            """
        
        let canonicalRequest = """
            PUT
            \(path)
            
            \(canonicalHeaders)
            
            \(signedHeaders)
            \(payloadHash)
            """
        
        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(config.s3Region)/s3/aws4_request"
        let stringToSign = """
            \(algorithm)
            \(amzDate)
            \(credentialScope)
            \(sha256Hash(string: canonicalRequest))
            """
        
        // Calculate signature
        let kDate = hmacSHA256(key: "AWS4\(config.s3SecretKey)".data(using: .utf8)!, data: dateStamp.data(using: .utf8)!)
        let kRegion = hmacSHA256(key: kDate, data: config.s3Region.data(using: .utf8)!)
        let kService = hmacSHA256(key: kRegion, data: "s3".data(using: .utf8)!)
        let kSigning = hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8)!)
        let signature = hmacSHA256(key: kSigning, data: stringToSign.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()
        
        // Create authorization header
        let authorization = "\(algorithm) Credential=\(config.s3AccessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }
    
    private func sha256Hash(string: String) -> String {
        sha256Hash(data: string.data(using: .utf8)!)
    }
    
    private func sha256Hash(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBuffer.baseAddress, key.count, dataBuffer.baseAddress, data.count, &hash)
            }
        }
        return Data(hash)
    }
}

enum UploadError: LocalizedError {
    case noConfig
    case invalidURL
    case invalidResponse
    case uploadFailed(Int)
    
    var errorDescription: String? {
        switch self {
        case .noConfig: return "No S3 configuration. Open Settings to configure."
        case .invalidURL: return "Invalid S3 URL"
        case .invalidResponse: return "Invalid response from server"
        case .uploadFailed(let code): return "Upload failed (HTTP \(code))"
        }
    }
}
