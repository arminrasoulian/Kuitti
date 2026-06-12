import Foundation

nonisolated struct OFFProduct: Sendable {
    var ean: String
    var productName: String?
    var productNameFI: String?
    var brands: String?
    var quantity: String?
    var categoriesTags: [String]

    var bestName: String? {
        let name = productNameFI?.isEmpty == false ? productNameFI : productName
        return name?.isEmpty == false ? name : nil
    }
}

/// Read-only Open Food Facts v2 client. No auth; custom User-Agent per OFF etiquette;
/// client-side throttle respecting the published 15 product-reads/min limit.
actor OpenFoodFactsClient {
    private let session: URLSession
    private var lastRequestAt: Date?
    private let minInterval: TimeInterval = 4

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Kuitti/1.0 (armin.rasoulian@sievo.com)"]
        session = URLSession(configuration: config)
    }

    /// Returns nil when OFF doesn't know the barcode (status 0) — a normal outcome for
    /// Finnish private labels, handled as a first-class fallback flow, not an error.
    func product(forBarcode ean: String) async throws -> OFFProduct? {
        if let last = lastRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                try await Task.sleep(for: .seconds(minInterval - elapsed))
            }
        }
        lastRequestAt = Date()

        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(ean)")!
        components.queryItems = [
            .init(name: "fields", value: "product_name,product_name_fi,brands,quantity,categories_tags")
        ]

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch let urlError as URLError {
            throw NetworkError(urlError)
        }
        guard let http = response as? HTTPURLResponse else { throw BarcodeError.offUnavailable }
        Log.off.info("OFF \(ean): HTTP \(http.statusCode), \(data.count)B")

        switch http.statusCode {
        case 200, 404:
            break // v2 returns 404 with a status-0 body for unknown products
        case 503, 429:
            throw BarcodeError.offRateLimited
        default:
            throw BarcodeError.offUnavailable
        }

        let dto: ResponseDTO
        do {
            dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            if http.statusCode == 404 { return nil }
            throw BarcodeError.offUnavailable
        }
        guard dto.status == 1, let product = dto.product else { return nil }
        return OFFProduct(
            ean: ean,
            productName: product.productName,
            productNameFI: product.productNameFI,
            brands: product.brands,
            quantity: product.quantity,
            categoriesTags: product.categoriesTags ?? []
        )
    }

    private nonisolated struct ResponseDTO: Decodable {
        struct ProductDTO: Decodable {
            var productName: String?
            var productNameFI: String?
            var brands: String?
            var quantity: String?
            var categoriesTags: [String]?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case productNameFI = "product_name_fi"
                case brands, quantity
                case categoriesTags = "categories_tags"
            }
        }
        var status: Int?
        var product: ProductDTO?
    }
}
