import SwiftUI

extension View {
    /// Preserve the editor's draft and report write failures even if its inline
    /// validation section is off screen. Never imply an unsuccessful save worked.
    func saveFailureAlert(isPresented: Binding<Bool>) -> some View {
        alert("Couldn’t save your changes", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn’t save your changes. Your input is still here. Try Save again.")
        }
    }
}
