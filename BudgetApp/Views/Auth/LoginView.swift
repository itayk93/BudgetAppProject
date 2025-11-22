import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: AuthViewModel
    @State private var isRegister = false
    @State private var showPassword = false

    init() {
        _vm = StateObject(wrappedValue: AuthViewModel(baseURL: AppConfig.baseURL))
    }

    var body: some View {
        ZStack {
#if os(iOS)
            Color(.systemGroupedBackground).ignoresSafeArea()
#else
            Color(NSColor.controlBackgroundColor).ignoresSafeArea()
#endif
            ScrollView {
                VStack(spacing: 18) {
                    // Header
                    VStack(spacing: 6) {
                        Text("ברוך הבא")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(isRegister ? "הרשמה" : "התחברות")
                            .font(.largeTitle).bold()
                    }

                    // Card
                    VStack(alignment: .trailing, spacing: 12) {
                        VStack(alignment: .trailing, spacing: 8) {
                            Text("שם משתמש או אימייל").font(.footnote).foregroundColor(.secondary)
                            TextField("לדוגמה: user או user@email.com", text: $vm.username)
#if os(iOS)
                                .textInputAutocapitalization(.never)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
#endif
                                .autocorrectionDisabled()
                                .padding(12)
#if os(iOS)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
#else
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.tertiaryLabelColor)))
#endif
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            Text("סיסמה").font(.footnote).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Group {
                                    if showPassword {
                                        TextField("••••••••", text: $vm.password)
#if os(iOS)
                                            .textContentType(.password)
                                            .textInputAutocapitalization(.never)
#endif
                                            .autocorrectionDisabled()
                                    } else {
                                        SecureField("••••••••", text: $vm.password)
#if os(iOS)
                                            .textContentType(.password)
#endif
                                    }
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
#if os(iOS)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
#else
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.tertiaryLabelColor)))
#endif
                        }

                        if isRegister {
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("אימייל").font(.footnote).foregroundColor(.secondary)
                                TextField("name@example.com", text: $vm.email)
#if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
#endif
                                    .autocorrectionDisabled()
                                    .padding(12)
#if os(iOS)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
#else
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.tertiaryLabelColor)))
#endif
                            }
                            HStack(spacing: 12) {
                                TextField("שם פרטי", text: $vm.firstName)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                                TextField("שם משפחה", text: $vm.lastName)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                            }
                        }

                        if let err = vm.errorMessage, !err.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                Text(err)
                                    .font(.footnote)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                        }

                        Button(action: {
                            Task {
                                print("🔵 [LOGIN] Button pressed")
                                if isRegister {
                                    print("🔵 [LOGIN] Registering...")
                                    await vm.register()
                                } else {
                                    print("🔵 [LOGIN] Logging in...")
                                    await vm.login()
                                }

                                // After successful login/register: persist userId and ensure the
                                // CashFlow dashboard is primed with the correct selected cash flow.
                                print("🔵 [LOGIN] isAuthenticated: \(vm.isAuthenticated), currentUser: \(vm.currentUser?.username ?? "nil")")
                                if vm.isAuthenticated, let user = vm.currentUser {
                                    print("🔵 [LOGIN] ✅ Login successful for user: \(user.username) (ID: \(user.id))")
                                    UserDefaults.standard.set(user.id, forKey: "auth.userId")
                                    // Load cash flows into the shared dashboard VM and pick the default
                                    print("🔵 [LOGIN] Loading cash flows from API...")
                                    await appState.cashFlowDashboardVM.loadInitial()
                                    print("🔵 [LOGIN] Loaded \(appState.cashFlowDashboardVM.cashFlows.count) cash flows")
                                    print("🔵 [LOGIN] appState.cashFlowDashboardVM.selectedCashFlow: \(appState.cashFlowDashboardVM.selectedCashFlow?.name ?? "nil")")
                                    if let defaultCF = appState.cashFlowDashboardVM.cashFlows.first(where: { $0.is_default == true }) ?? appState.cashFlowDashboardVM.cashFlows.first {
                                        print("🔵 [LOGIN] Setting selectedCashFlow to: \(defaultCF.name)")
                                        appState.cashFlowDashboardVM.selectedCashFlow = defaultCF
                                        print("🔵 [LOGIN] After set: \(appState.cashFlowDashboardVM.selectedCashFlow?.name ?? "nil")")
                                        UserDefaults.standard.set(defaultCF.id, forKey: "app.selectedCashFlowId")
                                    } else {
                                        print("🔵 [LOGIN] ❌ No cash flows available!")
                                    }
                                } else {
                                    print("🔵 [LOGIN] ❌ Login failed or user not found")
                                }
                            }
                        }) {
                            HStack {
                                Spacer()
                                if vm.loading { ProgressView().tint(.white) } else { Text(isRegister ? "הירשם" : "התחבר").bold() }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                            .foregroundColor(.white)
                        }
                        .disabled(vm.loading || vm.username.isEmpty || vm.password.isEmpty || (isRegister && vm.email.isEmpty))

                        Button(isRegister ? "כבר יש לך חשבון? התחבר" : "אין חשבון? הירשם") { isRegister.toggle() }
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
#if os(iOS)
                            .fill(Color(.systemBackground))
#else
                            .fill(Color(NSColor.windowBackgroundColor))
#endif
                            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            vm.updateBaseURL(appState.baseURL)
            Task { await vm.checkSession() }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AppState())
    }
}
