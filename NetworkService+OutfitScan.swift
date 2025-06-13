//
//  NetworkService+OutfitScan.swift
//  FitSpo
//
//  Calls the Cloud Function `scanOutfit` (Node 20, 2nd-gen) and
//  parses its canonical response into `[OutfitItem]`.
//

import FirebaseFunctions
import Foundation

extension NetworkService {

    /// Analyse an outfit image via Cloud Functions + Replicate.
    func scanOutfit(
        postId: String,
        imageURL: String,
        completion: @escaping (Result<[OutfitItem], Error>) -> Void
    ) {
        let payload: [String:Any] = [
            "postId"  : postId,
            "imageURL": imageURL
        ]

        Functions.functions(region: "us-central1")
            .httpsCallable("scanOutfit")
            .call(payload) { result, error in
                if let error { return completion(.failure(error)) }

                guard
                    let dict = result?.data as? [String:Any],
                    let json = try? JSONSerialization.data(withJSONObject: dict),
                    let response = try? JSONDecoder().decode(Response.self, from: json)
                else {
                    return completion(
                        .failure(NSError(
                            domain: "ScanOutfit",
                            code:   -1,
                            userInfo: [NSLocalizedDescriptionKey: "Malformed response"])
                        )
                    )
                }
                completion(.success(response.items))
            }
    }

    private struct Response: Decodable { let items: [OutfitItem] }
}
