//
//  NormalButtonStyle.swift
//  KoveMirror
//
//  Created by Matti Mustonen on 17.10.2026.
//
import SwiftUI

struct NormalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension ButtonStyle where Self == NormalButtonStyle {
    static var normalButtonStyle: NormalButtonStyle {
        NormalButtonStyle()
    }
}

extension View {
    func normalButtonStyle() -> some View {
        buttonStyle(.normalButtonStyle)
    }
}
