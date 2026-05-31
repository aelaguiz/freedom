import Foundation

enum ThreadDetailHumanOnlyRejection {
    private static let code: Int64 = -32043
    private static let unavailableMessage = "Thread unavailable."

    static func message(for error: Error) -> String? {
        guard let clientError = error as? AppServerClientError,
              case let .server(serverError) = clientError,
              serverError.code == code else {
            return nil
        }
        return unavailableMessage
    }
}
