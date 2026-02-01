import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#fdf6ec").ignoresSafeArea()

                VStack(spacing: 0) {

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Badminton\nAI Coach")
                                .font(.custom("Inter_28pt-ExtraBold", size: 55))
                                .foregroundColor(Color(hex: "#1A202C"))
                                .multilineTextAlignment(.center)

                            Image("logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 52.5)
                        }

                        Text("bbb birdie elite center beep")
                            .font(.custom("Inter_28pt-SemiBoldItalic", size: 18))
                            .foregroundColor(Color(hex: "#1A202C"))
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 50)

                    VStack(spacing: 20) {
                        NavButton(title: "Form Correction") {
                            FormView()
                        }

                        NavButton(title: "Match Analysis") {
                            MatchView()
                        }

                        NavButton(title: "About Us") {
                            AboutView()
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

/// Reusable button that matches your RN styling
private struct NavButton<Destination: View>: View {
    let title: String
    let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            Text(title)
                .font(.custom("Inter_24pt-Regular", size: 26))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color(hex: "#9fc9ae"))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.35), radius: 13, x: 0, y: 4)
        }
        .buttonStyle(.plain) // safe here because label is fully custom
    }
}
