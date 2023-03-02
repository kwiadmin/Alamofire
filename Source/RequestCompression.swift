//
//  DeflateRequestCompression.swift
//
//  Copyright (c) 2023 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// `RequestAdapter` which compresses incoming `URLRequest` bodies using the `deflate` `Content-Encoding`.
///
/// - Note: Most requests to most APIs are small and so would only be slowed down by applying this adapter. Measure the
///         size of your request bodies and the performance impact of using this adapter before use.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DeflateRequestCompressor: RequestInterceptor {
    /// Type that determines the action taken when the `Request` already has a `Content-Encoding` header.
    public enum DuplicateHeaderBehavior {
        /// Throws a `DuplicateHeaderError`. The default.
        case error
        /// Replaces the existing header value with `deflate`.
        case replace
        /// Silently skips compression.
        case skip
    }

    /// `Error` produced when the incoming `URLRequest` already has a `Content-Encoding` header, when configured to do
    /// so.
    public struct DuplicateHeaderError: Error {}

    /// Behavior to use when the incoming `URLRequest` already has a `Content-Encoding` header.
    public let duplicateHeaderBehavior: DuplicateHeaderBehavior

    /// Creates an instance.
    ///
    /// - Parameter duplicateHeaderBehavior: <#duplicateHeaderBehavior description#>
    public init(duplicateHeaderBehavior: DuplicateHeaderBehavior = .error) {
        self.duplicateHeaderBehavior = duplicateHeaderBehavior
    }

    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        // No need to compress unless we have body data. No support for compressing streams.
        guard let bodyData = urlRequest.httpBody else {
            completion(.success(urlRequest))
            return
        }

        if urlRequest.headers.value(for: "Content-Encoding") != nil {
            switch duplicateHeaderBehavior {
            case .error:
                completion(.failure(DuplicateHeaderError()))
                return
            case .replace:
                // Header will be replaced once the body data is compressed.
                break
            case .skip:
                completion(.success(urlRequest))
                return
            }
        }

        var compressedRequest = urlRequest

        do {
            compressedRequest.httpBody = try deflate(bodyData)
            compressedRequest.headers.update(.contentEncoding("deflate"))
            completion(.success(compressedRequest))
        } catch {
            completion(.failure(error))
        }
    }

    func deflate(_ data: Data) throws -> Data {
        var output = Data([0x78, 0x5E]) // Header
        try output.append((data as NSData).compressed(using: .zlib) as Data)
        var checksum = adler32Checksum(of: data).bigEndian
        output.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

        return output
    }

    @inline(__always) // Still slower than libz, but 50% faster than it was.
    func adler32Checksum(of data: Data) -> UInt32 {
        var s1: UInt32 = 1 & 0xFFFF
        var s2: UInt32 = (1 >> 16) & 0xFFFF
        let prime: UInt32 = 65_521

        for byte in data {
            s1 += UInt32(byte)
            if s1 >= prime { s1 = s1 % prime }
            s2 += s1
            if s2 >= prime { s2 = s2 % prime }
        }

        return (s2 << 16) | s1
    }
}
