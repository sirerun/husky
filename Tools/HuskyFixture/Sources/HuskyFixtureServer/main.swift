import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import HuskyFixture

@main
enum HuskyFixtureServer {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.contains("--fixture-mode") else {
      throw UsageError("Pass --fixture-mode to start the local deterministic fixture.")
    }

    let port = try Self.port(from: arguments)
    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: port),
      transportSecurity: .plaintext
    )
    let server = GRPCServer(transport: transport, services: [HuskyFixtureService()])

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.serve() }
      let address = try await transport.listeningAddress
      print(
        "Husky local fixture listening at \(address); deterministic demo data, plaintext loopback only, not a production backend"
      )
    }
  }

  private static func port(from arguments: [String]) throws -> Int {
    guard let index = arguments.firstIndex(of: "--port") else { return 50_051 }
    guard arguments.indices.contains(index + 1), let port = Int(arguments[index + 1]),
      (0...65_535).contains(port)
    else {
      throw UsageError("--port must be an integer from 0 through 65535.")
    }
    return port
  }
}

private struct UsageError: LocalizedError {
  var message: String
  var errorDescription: String? { message }

  init(_ message: String) { self.message = message }
}
