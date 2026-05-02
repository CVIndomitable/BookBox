import SwiftUI

struct LoginView: View {
    @StateObject private var auth = AuthService.shared
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("密码（至少 8 位）", text: $password)

                    if mode == .register {
                        TextField("邮箱（可选）", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        TextField("显示名（可选）", text: $displayName)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text(mode.rawValue)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("BookBox")
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .login:
                    try await NetworkService.shared.login(username: username, password: password)
                case .register:
                    try await NetworkService.shared.register(
                        username: username,
                        password: password,
                        email: email.isEmpty ? nil : email,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

#Preview {
    LoginView()
}
