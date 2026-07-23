import AuthenticationServices
import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    connectionHero
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await session.completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 15))

                    VStack(spacing: 12) {
                        providerCard(.gmail, title: "Gmail", subtitle: "Primary source for recruiter messages, interviews, offers and rejections.", systemImage: "envelope.fill", color: .red)
                        providerCard(.linkedin, title: "LinkedIn", subtitle: "Links your identity and approved LinkedIn permissions.", systemImage: "link", color: .blue)
                        providerCard(.indeed, title: "Indeed", subtitle: "Available after Indeed partner credentials are approved.", systemImage: "briefcase.fill", color: .indigo)
                    }
                    infoCard
                }.padding(16).padding(.bottom, 40)
            }
            .background(Color.radarCanvas)
            .navigationTitle("Connections")
        }
    }

    private var connectionHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTOMATION HUB").font(.caption2.weight(.black)).tracking(1.6).foregroundStyle(.radarMint)
            Text("Connect once.\nLet the radar watch.").font(.system(size: 31, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Gmail powers the reliable status scan. Other providers are added only through their approved APIs.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(LinearGradient(colors: [.radarInk, .radarNight], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

    private func providerCard(_ provider: AppSession.Provider, title: String, subtitle: String, systemImage: String, color: Color) -> some View {
        let connected = session.connectedProviders.contains(provider)
        return HStack(spacing: 14) {
            Image(systemName: systemImage).font(.title3.bold()).foregroundStyle(color).frame(width: 46, height: 46).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 8)
            Button(connected ? "Connected" : "Connect") {
                Task {
                    if connected { session.disconnect(provider) }
                    else { await session.connect(provider) }
                }
            }
            .font(.caption.weight(.black)).foregroundStyle(connected ? .radarMint : .radarInk).padding(.horizontal, 11).padding(.vertical, 9).background(connected ? Color.radarMint.opacity(0.12) : Color.radarCanvas, in: Capsule())
        }.padding(15).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var infoCard: some View {
        Label("The app never stores your LinkedIn, Indeed or Gmail password. OAuth tokens belong on the secure backend and can be revoked.", systemImage: "lock.shield.fill")
            .font(.caption).foregroundStyle(.secondary).padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
