// pepis/GroupStore.swift
import Foundation

final class GroupStore {
    private(set) var groups: [Group] = []
    var onChange: (() -> Void)?

    private let supportDir: URL
    private let groupsFile: URL
    private let contextDir: URL

    init(supportDir: URL = GroupStore.defaultSupportDir()) {
        self.supportDir = supportDir
        self.groupsFile = supportDir.appendingPathComponent("groups.json")
        self.contextDir = supportDir.appendingPathComponent("context")
        createDirectoriesIfNeeded()
        load()
    }

    static func defaultSupportDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("pepis")
    }

    func save(group: Group) {
        groups.append(group)
        persist()
        createContextFileIfNeeded(for: group)
        onChange?()
    }

    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        persist()
        onChange?()
    }

    func contextFileURL(for group: Group) -> URL {
        contextDir.appendingPathComponent("\(group.id.uuidString).md")
    }

    // MARK: - Private

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: groupsFile) else { return }
        groups = (try? JSONDecoder().decode([Group].self, from: data)) ?? []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsFile, options: .atomic)
        }
    }

    private func createContextFileIfNeeded(for group: Group) {
        let url = contextFileURL(for: group)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
