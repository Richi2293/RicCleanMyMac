import SwiftUI

/// Helper view modifier for showing confirmation dialog
struct CleanupConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let items: [CleanupItem]
    let totalSize: Int64
    let onConfirm: () -> Void
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Confirm Cleanup",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Delete", role: .destructive) {
                    onConfirm()
                    isPresented = false
                }
            } message: {
                Text(confirmationMessage)
            }
    }
    
    private var confirmationMessage: String {
        let itemCount = items.count
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize)
        
        if itemCount == 1 {
            return "Are you sure you want to delete \"\(items.first?.name ?? "this item")\"? This will free up \(formattedSize) of disk space. This action cannot be undone."
        } else {
            return "Are you sure you want to delete \(itemCount) items? This will free up \(formattedSize) of disk space. This action cannot be undone."
        }
    }
}

extension View {
    func cleanupConfirmation(
        isPresented: Binding<Bool>,
        items: [CleanupItem],
        totalSize: Int64,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(CleanupConfirmationModifier(
            isPresented: isPresented,
            items: items,
            totalSize: totalSize,
            onConfirm: onConfirm
        ))
    }
}

