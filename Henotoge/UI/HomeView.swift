import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Background()
                VStack(spacing: 28) {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("henotoge")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .pink], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("4 LANE RHYTHM GAME")
                            .font(.caption.bold())
                            .tracking(4)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 14) {
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
                        NavigationLink {
                            SettingsView()
                        } label: {
                            MenuButton(title: "設定", sub: "ハイスピード・タイミング", color: .gray)
                        }
                    }
                    .padding(.horizontal, 28)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 520)
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
                Text(title).font(.title3.bold())
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(color)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.6), lineWidth: 1.5))
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
