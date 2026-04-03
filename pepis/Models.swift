// pepis/Models.swift
import Foundation
import CoreGraphics

struct WindowSnapshot: Codable {
    var appBundleID: String
    var appName: String
    var windowIndex: Int
    // CGRect is not Codable — store components as Doubles
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
}

extension WindowSnapshot {
    var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    init(appBundleID: String, appName: String, windowIndex: Int, frame: CGRect) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowIndex = windowIndex
        self.frameX = frame.origin.x
        self.frameY = frame.origin.y
        self.frameWidth = frame.size.width
        self.frameHeight = frame.size.height
    }
}

struct Group: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var windows: [WindowSnapshot]
}
