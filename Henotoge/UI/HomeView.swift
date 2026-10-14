import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Background()
                HStack(spacing: 40) {
                    VStack(spacing: 6) {
                        Text("henotoge")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .pink], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("6 LANE · 2 FINGER RHYTHM GAME")
                            .font(.caption.bold())
                            .tracking(3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        NavigationLink {
                            SongSelectView()
                        } label: {
                            MenuButton(title: "FREE PLAY", sub: "\(Library.shared.songs.count)曲", color: .cyan)
                        }
                        NavigationLink {
                            CourseSelectView()
                        } label: {
                            MenuButton(title: "段位認定", sub: "\(Library.shared.courses.count)コース", color: .pink)
                        }
                        HStack(spacing: 10) {
                            NavigationLink {
                                HowToPlayView()
                            } label: {
                                MenuButton(title: "遊び方", sub: "ノーツの種類", color: .orange)
                            }
                            NavigationLink {
                                SettingsView()
                            } label: {
                                MenuButton(title: "設定", sub: "速さ・タイミング", color: .gray)
                            }
                        }
                    }
                    .frame(maxWidth: 380)
                }
                .padding(.horizontal, 40)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.pink)
    }
}

struct MenuButton: View {
    let title: String
    let sub: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(color)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.6), lineWidth: 1.5))
        )
    }
}

/// 画面共通の背景
struct Background: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.12), Color(red: 0.02, green: 0.02, blue: 0.05)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
