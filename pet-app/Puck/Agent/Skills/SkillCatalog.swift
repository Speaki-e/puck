//
//  SkillCatalog.swift
//  Puck
//
//  What is installed, and where from.
//
//  Both locations the coding CLI reads: `~/.claude/skills` for everything on
//  this machine, and the project's own `.claude/skills` for what the team
//  shares. A skill in both is listed once, as the project's -- that is which
//  one wins when the CLI loads them, and showing two would suggest otherwise.
//

import Foundation

enum SkillCatalog {
    static let directoryName = "skills"
    static let manifestName = "SKILL.md"

    /// `~/.claude/skills`.
    static var personalDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Everything found, project first, each list alphabetical -- a list that
    /// reorders itself between reads is one nobody can scan twice.
    static func discover(
        projectPath: String?,
        fileManager: FileManager = .default
    ) -> [Skill] {
        var byName: [String: Skill] = [:]
        var order: [String] = []

        func take(_ skills: [Skill]) {
            for skill in skills {
                if byName[skill.name] == nil { order.append(skill.name) }
                // Project wins: `take` is called with it first.
                if byName[skill.name] == nil { byName[skill.name] = skill }
            }
        }

        if let projectPath {
            let directory = URL(fileURLWithPath: projectPath, isDirectory: true)
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
            take(skills(in: directory, source: .project, fileManager: fileManager))
        }
        take(skills(in: personalDirectory, source: .personal, fileManager: fileManager))
        return order.compactMap { byName[$0] }
    }

    /// One directory's worth. A directory without a SKILL.md is not a skill
    /// and is skipped rather than reported as broken: `.claude/skills` holds
    /// other things too.
    static func skills(in directory: URL, source: Skill.Source, fileManager: FileManager = .default) -> [Skill] {
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.sorted().compactMap { entry in
            let manifest = directory.appendingPathComponent(entry, isDirectory: true)
                .appendingPathComponent(manifestName)
            guard let contents = try? String(contentsOf: manifest, encoding: .utf8),
                  let parsed = SkillFrontmatter.parse(contents) else { return nil }
            // The directory name is the fallback: a manifest that forgot its
            // `name:` is still a skill, and the folder is what the CLI keys on.
            let name = parsed.name.isEmpty ? entry : parsed.name
            return Skill(name: name, description: parsed.description, path: manifest.path, source: source)
        }
    }
}
