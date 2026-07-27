// PersonAvatarView.swift

import SwiftUI

/// Contact photo when resolvable, warm initials otherwise.
struct PersonAvatarView: View {
    let person: Person
    var size: CGFloat = 44

    @Environment(AppServices.self) private var services
    @State private var thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData, let image = UIImage(data: thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(.emberAmber), Color(.emberTerracotta)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: person.contactID) {
            guard let contactID = person.contactID else {
                thumbnailData = nil
                return
            }
            thumbnailData = await services.contacts.resolve(contactID)?.thumbnailData
        }
    }

    private var initials: String {
        let words = person.displayNameCache.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first)
        return letters.isEmpty ? "•" : String(letters).uppercased()
    }
}
