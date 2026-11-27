import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct OperationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Stage: Int, Codable, Hashable { case processing = 1, waiting, saved, failed, cancelled }
        let stage: Stage
        let status: String
    }
    let operationID: UUID
    let title: String
    let ticker: String
    let quantity: String?
    let amount: String?
    let symbol: String
}
