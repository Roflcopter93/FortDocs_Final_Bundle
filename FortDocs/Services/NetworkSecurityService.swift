import Foundation
import Security
import CryptoKit

/// Provides a secure `URLSession` configured for certificate pinning.
///
/// CloudKit traffic is normally secured by Apple's system frameworks, but an
/// additional layer of defence can help protect against man‑in‑the‑middle
/// attacks when communicating with your own web services. This service
/// validates the server's certificate by comparing the SHA‑256 hash of the
/// public key against a list of known good values. Only if the hash matches
/// will the connection proceed.
public final class NetworkSecurityService: NSObject {
    /// Shared singleton instance for convenience. You can create additional
    /// instances if you need to pin against different keys.
    public static let shared = NetworkSecurityService()

    /// The Base64‑encoded SHA‑256 hashes of the subject public keys that are
    /// permitted for your server. Replace these values with the actual hashes
    /// for the certificates you wish to pin. For example, you can obtain the
    /// hash of a certificate's public key using the `openssl x509 -pubkey` and
    /// `openssl dgst -sha256` commands or via a security audit tool.
    private let pinnedKeyHashes: Set<Data> = [
        // Example placeholder hash. You must replace this with the real hash
        // from Apple's CloudKit servers or your own backend.
        Data(base64Encoded: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")!
    ]

    /// Create a `URLSession` configured to use this object as its delegate.
    /// The returned session will perform certificate pinning on every TLS
    /// challenge. If the challenge fails pinning, the request is cancelled.
    /// - Returns: A secure `URLSession` instance.
    public func makeSecureSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
}

// MARK: - URLSessionDelegate

extension NetworkSecurityService: URLSessionDelegate {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // For non‑server trust challenges we perform default handling.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust. This step verifies the signature chain and
        // ensures the certificate is issued by a trusted root authority.
        var secResult = SecTrustResultType.invalid
        let status = SecTrustEvaluate(serverTrust, &secResult)
        guard status == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the leaf certificate's public key and compute its SHA‑256 hash.
        guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let keyHash = sha256(data: publicKeyData)

        // Compare the hash against our pinned values. If it matches, we allow the
        // connection to proceed; otherwise we cancel to prevent MITM.
        if pinnedKeyHashes.contains(keyHash) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Compute the SHA‑256 digest of the supplied data using CryptoKit.
    /// - Parameter data: The data to hash.
    /// - Returns: A 32‑byte Data value representing the SHA‑256 hash.
    private func sha256(data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}