import SwiftUI

@MainActor
struct AuthView: View {
    @EnvironmentObject private var state: AppState
    @State private var register = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    #if DEBUG
    @State private var showBackend = false
    @State private var backend = ""
    #endif
        // UI tests in the Simulator: the strong-password autofill overlay steals focus from SecureField.
    private static var uiTesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "figure.golf").font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                        Text("Make every rep count.").font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Live form coaching for golf, basketball, tennis and pickleball. Place your phone on a tripod and practise.")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                }
                Section(register ? "Create your account" : "Welcome back") {
                    Picker("Account action", selection: $register) {
                        Text("Log in").tag(false)
                        Text("Register").tag(true)
                    }.pickerStyle(.segmented)
                    if register {
                        TextField("Name", text: $name).textContentType(.name).autocorrectionDisabled()
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if Self.uiTesting {
                        TextField("Password", text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(register ? .newPassword : .password)
                    }
                    if register { Text("Use at least 8 characters.").font(.caption).foregroundStyle(.secondary) }
                    if let error = error { ErrorNotice(message: error) }
                    Button {
                        busy = true; error = nil
                        Task {
                            do {
                                try await state.authenticate(email: email, password: password, name: name, register: register)
                                password = ""
                                await state.launch()
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() }
                            Text(register ? "Create account" : "Log in").fontWeight(.semibold)
                            Spacer()
                        }.frame(minHeight: 44)
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty || (register && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.count < 8)))
                }
                if let error = state.error { Section { ErrorNotice(message: error) } }
                #if DEBUG
                Section("Development") {
                    Button("Backend URL") { backend = state.backendURL; showBackend = true }
                    Text("On a real iPhone, localhost is the phone itself. Use your server’s LAN hostname, such as http://formcoach.local:8000.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #endif
            }
            .navigationTitle("FormCoach")
            #if DEBUG
            .sheet(isPresented: $showBackend) {
                NavigationStack {
                    Form {
                        TextField("Backend URL", text: $backend).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Save URL") {
                            do { try state.changeBackend(backend); showBackend = false }
                            catch { self.error = error.localizedDescription; showBackend = false }
                        }
                    }.navigationTitle("Backend")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showBackend = false } } }
                }
            }
            #endif
        }
    }
}
