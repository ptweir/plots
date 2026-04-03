// plots/GroupStore.swift
import Foundation

final class GroupStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: UUID?
    var onChange: (() -> Void)?

    private let supportDir: URL
    private let groupsFile: URL
    private let contextDir: URL
    private let currentFile: URL

    init(supportDir: URL = GroupStore.defaultSupportDir()) {
        self.supportDir = supportDir
        self.groupsFile = supportDir.appendingPathComponent("groups.json")
        self.contextDir = supportDir.appendingPathComponent("context")
        self.currentFile = supportDir.appendingPathComponent("current.json")
        createDirectoriesIfNeeded()
        load()
        loadCurrentGroup()
    }

    static func defaultSupportDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("plots")
    }

    func save(group: Group) {
        groups.append(group)
        persist()
        createContextFileIfNeeded(for: group)
        onChange?()
    }

    func update(id: UUID, windows: [WindowSnapshot]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].windows = windows
        persist()
        onChange?()
    }

    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        if currentGroupID == id {
            currentGroupID = nil
            persistCurrentGroup()
        }
        persist()
        onChange?()
    }

    func setCurrentGroup(id: UUID?) {
        currentGroupID = id
        persistCurrentGroup()
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

    private func loadCurrentGroup() {
        guard let data = try? Data(contentsOf: currentFile),
              let uuidString = try? JSONDecoder().decode(String.self, from: data),
              let id = UUID(uuidString: uuidString),
              groups.contains(where: { $0.id == id }) else {
            currentGroupID = nil
            return
        }
        currentGroupID = id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsFile, options: .atomic)
        }
    }

    private func persistCurrentGroup() {
        if let id = currentGroupID {
            if let data = try? JSONEncoder().encode(id.uuidString) {
                try? data.write(to: currentFile, options: .atomic)
            }
        } else {
            try? FileManager.default.removeItem(at: currentFile)
        }
    }

    private func createContextFileIfNeeded(for group: Group) {
        let url = contextFileURL(for: group)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
