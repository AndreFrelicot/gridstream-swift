import Foundation
import GridStreamAPI
import Vapor

nonisolated struct AuthRoutes: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("api", "v1", "auth")
        auth.get("session", use: session)
        auth.post("login", use: login)
        auth.post("logout", use: logout)
    }

    @Sendable
    private func session(req: Request) async throws -> AuthSessionResponse {
        req.application.serverAuthManager.sessionStatus(for: req)
    }

    @Sendable
    private func login(req: Request) async throws -> Response {
        let payload = try req.content.decode(LoginRequest.self)
        let monitor = req.application.connectionMonitor
        do {
            let response = try await req.application.serverAuthManager.login(pin: payload.pin, request: req)
            monitor?.recordSignIn(from: req.clientAddress, userAgent: req.userAgent, outcome: .succeeded)
            return response
        } catch let abort as AbortError where abort.status == .unauthorized || abort.status == .tooManyRequests {
            monitor?.recordSignIn(
                from: req.clientAddress,
                userAgent: req.userAgent,
                outcome: abort.status == .unauthorized ? .wrongPIN : .blocked
            )
            throw abort
        }
    }

    @Sendable
    private func logout(req: Request) async throws -> Response {
        req.application.connectionMonitor?.recordSignOut(from: req.clientAddress, userAgent: req.userAgent)
        return req.application.serverAuthManager.logoutResponse(for: req)
    }
}
