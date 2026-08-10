import Foundation
import UIKit

#if canImport(MSAL)
@preconcurrency import MSAL
#endif

enum MicrosoftAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case accountNotFound
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Outlook isn't configured yet. Register an iOS public client in Microsoft Entra and add MicrosoftClientID to project.yml."
        case .cancelled: "Microsoft sign-in was cancelled."
        case .accountNotFound: "This Microsoft account is no longer available. Reconnect Outlook."
        case .underlying(let message): message
        }
    }
}

@MainActor
final class MicrosoftAuthService {
    nonisolated static let mailScopes = ["User.Read", "Mail.Read"]
    nonisolated static let calendarScopes = ["User.Read", "Calendars.Read"]
    nonisolated static let allScopes = ["User.Read", "Mail.Read", "Calendars.Read"]

    var isConfigured: Bool { AppConfig.microsoftClientID != nil }

    func connectAccount() async throws -> EmailAccount {
        #if canImport(MSAL)
        let application = try makeApplication()
        let presenter = try rootViewController()
        let web = MSALWebviewParameters(authPresentationViewController: presenter)
        let parameters = MSALInteractiveTokenParameters(scopes: Self.allScopes, webviewParameters: web)
        parameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: parameters) { result, error in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                    return
                }
                guard let result,
                      let identifier = result.account.identifier,
                      let email = result.account.username,
                      !email.isEmpty else {
                    continuation.resume(throwing: MicrosoftAuthError.accountNotFound)
                    return
                }
                let name = (result.account.accountClaims?["name"] as? String) ?? email
                continuation.resume(returning: EmailAccount(
                    provider: .outlook,
                    providerAccountID: identifier,
                    email: email,
                    displayName: name
                ))
            }
        }
        #else
        throw MicrosoftAuthError.notConfigured
        #endif
    }

    func accessToken(for accountID: String, scopes: [String] = MicrosoftAuthService.allScopes) async -> String? {
        #if canImport(MSAL)
        guard let application = try? makeApplication(),
              let account = try? application.account(forIdentifier: accountID) else { return nil }
        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        return await withCheckedContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { result, _ in
                continuation.resume(returning: result?.accessToken)
            }
        }
        #else
        return nil
        #endif
    }

    func removeAccount(_ accountID: String) {
        #if canImport(MSAL)
        guard let application = try? makeApplication(),
              let account = try? application.account(forIdentifier: accountID) else { return }
        try? application.remove(account)
        #endif
    }

    @discardableResult
    func handle(_ url: URL, sourceApplication: String? = nil) -> Bool {
        #if canImport(MSAL)
        return MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: sourceApplication)
        #else
        return false
        #endif
    }

    #if canImport(MSAL)
    private func makeApplication() throws -> MSALPublicClientApplication {
        guard let clientID = AppConfig.microsoftClientID else { throw MicrosoftAuthError.notConfigured }
        let authorityURL = URL(string: "https://login.microsoftonline.com/\(AppConfig.microsoftTenantID)")!
        let authority: MSALAADAuthority
        do { authority = try MSALAADAuthority(url: authorityURL) }
        catch { throw MicrosoftAuthError.underlying(error.localizedDescription) }
        let config = MSALPublicClientApplicationConfig(
            clientId: clientID,
            redirectUri: AppConfig.microsoftRedirectURI,
            authority: authority
        )
        do { return try MSALPublicClientApplication(configuration: config) }
        catch { throw MicrosoftAuthError.underlying(error.localizedDescription) }
    }
    #endif

    private func rootViewController() throws -> UIViewController {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard let root = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController else {
            throw MicrosoftAuthError.underlying("No window is available to present Microsoft sign-in.")
        }
        return root
    }

    nonisolated private static func map(_ error: Error) -> MicrosoftAuthError {
        let value = error as NSError
        #if canImport(MSAL)
        if value.domain == MSALErrorDomain, value.code == MSALError.userCanceled.rawValue { return .cancelled }
        #endif
        return .underlying(error.localizedDescription)
    }
}
