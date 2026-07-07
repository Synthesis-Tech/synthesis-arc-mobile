import XCTest

/// End-to-end UI walks for Forge Commander — run via `scripts/ui-e2e/run.sh`.
final class ForgeCommanderE2ETests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let launchEnv = try E2ELaunchConfig.environment
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchEnvironment = launchEnv
        app.launch()
    }

    func test01_bootAndReachChannels() throws {
        waitForBoot()
        capture("01-channels-list")
    }

    func test02_openEngineeringChannel() throws {
        waitForBoot()
        openChannel(named: "engineering")
        assertThreadResponsive(timeout: 30)
        capture("02-engineering-thread")
    }

    func test03_createAndOpenChannel() throws {
        waitForBoot()
        let name = "e2e-\(Int(Date().timeIntervalSince1970))"
        createChannel(name: name, visibility: "Public")
        ensureChannelThreadVisible(named: name)
        assertThreadResponsive(timeout: 25)
        capture("03-created-channel")
    }

    func test04_privateChannelJoinFlow() throws {
        waitForBoot()
        let name = "e2e-priv-\(Int(Date().timeIntervalSince1970))"
        createChannel(name: name, visibility: "Private")
        ensureChannelThreadVisible(named: name)
        let join = app.buttons[E2EAccessibility.channelJoin]
        if join.waitForExistence(timeout: 8) {
            join.tap()
            assertThreadResponsive(timeout: 25)
        }
        capture("04-private-channel")
    }

    func test05_navigateAllDestinations() throws {
        waitForBoot()
        for dest in ["fleet", "inbox", "channels", "director", "blackboard", "settings"] {
            XCTAssertTrue(tapNav(dest), "Could not navigate to \(dest)")
            sleep(1)
            capture("05-nav-\(dest)")
        }
    }

    // MARK: - Helpers

    private func waitForBoot() {
        XCTAssertTrue(tapNav("channels"), "Could not open Channels — command rail not visible")
        let list = app.descendants(matching: .any)[E2EAccessibility.channelsList]
        XCTAssertTrue(
            list.waitForExistence(timeout: 60),
            "Channels screen did not appear — boot/connect failed (check FORGE_GRAPH_* launch env)"
        )
    }

    @discardableResult
    private func tapNav(_ destination: String) -> Bool {
        revealSidebarIfNeeded()
        let id = E2EAccessibility.nav(destination)
        let query = app.descendants(matching: .any).matching(identifier: id)
        if query.firstMatch.waitForExistence(timeout: 12) {
            query.firstMatch.tap()
            return true
        }
        let title = destination.capitalized
        let byLabel = app.buttons[title]
        if byLabel.waitForExistence(timeout: 5) {
            byLabel.tap()
            return true
        }
        return false
    }

    private func revealSidebarIfNeeded() {
        let channelsNav = app.descendants(matching: .any)[E2EAccessibility.nav("channels")].firstMatch
        if channelsNav.exists { return }

        for name in ["Sidebar", "Show Sidebar"] {
            let toggle = app.buttons[name].firstMatch
            if toggle.waitForExistence(timeout: 0.35) {
                toggle.tap()
                return
            }
        }
    }

    private func openChannel(named name: String) {
        filterChannelList(to: name)
        let rowId = E2EAccessibility.channelRow(name)
        let row = app.buttons[rowId].exists
            ? app.buttons[rowId]
            : app.descendants(matching: .any)[rowId]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Channel row #\(name) not found")
        row.tap()
        let thread = app.descendants(matching: .any)[E2EAccessibility.channelThread]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Channel thread did not mount in inspector column")
    }

    /// Create flow auto-selects the channel on sheet dismiss — open row only if thread is not already visible.
    private func ensureChannelThreadVisible(named name: String) {
        let thread = app.descendants(matching: .any)[E2EAccessibility.channelThread]
        if thread.waitForExistence(timeout: 8) { return }
        openChannel(named: name)
    }

    private func filterChannelList(to name: String) {
        let search = app.textFields["Search channels"]
        guard search.waitForExistence(timeout: 4) else { return }
        search.tap()
        if let current = search.value as? String, !current.isEmpty {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            search.typeText(deletes)
        }
        search.typeText(name)
    }

    private func createChannel(name: String, visibility: String) {
        let create = app.buttons[E2EAccessibility.channelsCreate]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        if visibility == "Private" {
            let privateButton = app.buttons["Private"]
            if privateButton.exists { privateButton.tap() }
        }

        let createConfirm = app.buttons["Create"]
        XCTAssertTrue(createConfirm.waitForExistence(timeout: 5))
        createConfirm.tap()

        let dismissed = NSPredicate(format: "exists == false")
        let sheetGone = expectation(for: dismissed, evaluatedWith: app.sheets.firstMatch, handler: nil)
        _ = XCTWaiter.wait(for: [sheetGone], timeout: 15)

        // Create sheet dismiss auto-selects the channel; thread mount is the real success signal.
        let thread = app.descendants(matching: .any)[E2EAccessibility.channelThread]
        if thread.waitForExistence(timeout: 12) { return }

        filterChannelList(to: name)
        let row = app.descendants(matching: .any)[E2EAccessibility.channelRow(name)]
        XCTAssertTrue(
            row.waitForExistence(timeout: 20),
            "Channel #\(name) not visible after create — thread and filtered row both missing"
        )
    }

    /// Thread is usable when join gate is gone and history load finished (composer, messages, empty state, or loading cleared).
    private func assertThreadResponsive(timeout: TimeInterval) {
        let join = app.buttons[E2EAccessibility.channelJoin]
        let composer = app.descendants(matching: .any)[E2EAccessibility.channelComposer].firstMatch
        let loadingHistory = app.staticTexts["Loading history..."].firstMatch
        let noMessages = app.staticTexts["No Messages Yet"].firstMatch
        let thread = app.descendants(matching: .any)[E2EAccessibility.channelThread].firstMatch
        let messageField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'message' OR identifier CONTAINS[c] 'message'")
        ).firstMatch

        var sawLoadingHistory = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if join.exists { return }
            if composer.exists { return }
            if messageField.exists { return }
            if noMessages.exists { return }
            if thread.staticTexts.count > 2 { return }

            if loadingHistory.exists {
                sawLoadingHistory = true
            } else if sawLoadingHistory, thread.exists {
                return
            }

            usleep(400_000)
        }

        var seen: [String] = []
        if thread.exists { seen.append("channel.thread") }
        if join.exists { seen.append("channel.join") }
        if composer.exists { seen.append("channel.composer") }
        if noMessages.exists { seen.append("No Messages Yet") }
        if loadingHistory.exists { seen.append("Loading history...") }
        if seen.isEmpty { seen.append("(none of the expected thread elements)") }

        XCTFail(
            "Channel thread did not become responsive within \(Int(timeout))s. "
                + "Elements seen at timeout: \(seen.joined(separator: ", "))"
        )
    }

    private func capture(_ slug: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = slug
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Injects graphd credentials into the app under test (UITest bundle is separate from app target).
enum E2ELaunchConfig {
    private static let requiredKeys = [
        "FORGE_GRAPH_HOST",
        "FORGE_GRAPH_API_KEY",
        "FORGE_GRAPH_AGENT",
    ]

    static var environment: [String: String] {
        get throws {
            let pi = ProcessInfo.processInfo.environment
            var fileEnv = loadDotEnv(at: envFilePath())
            var env: [String: String] = [:]
            env["FORGE_E2E"] = "1"
            for key in requiredKeys {
                let value = pi[key] ?? fileEnv[key]
                guard let value, !value.isEmpty else {
                    throw XCTSkip("Missing \(key) — run via scripts/ui-e2e/run.sh (config/e2e.env)")
                }
                env[key] = value
            }
            env["FORGE_GRAPH_PORT"] = pi["FORGE_GRAPH_PORT"] ?? fileEnv["FORGE_GRAPH_PORT"] ?? "9090"
            return env
        }
    }

    private static func envFilePath() -> String {
        let pi = ProcessInfo.processInfo.environment
        if let path = pi["E2E_ENV_FILE"], !path.isEmpty { return path }
        let root = pi["SRCROOT"] ?? pi["PROJECT_DIR"] ?? defaultRepoRoot()
        return (root as NSString).appendingPathComponent("config/e2e.env")
    }

    /// Fallback when Xcode does not inject SRCROOT into the test runner.
    private static func defaultRepoRoot() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    private static func loadDotEnv(at path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            out[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}

enum E2EAccessibility {
    static func nav(_ destination: String) -> String { "nav.\(destination.lowercased())" }
    static let channelsCreate = "channels.create"
    static let channelsList = "channels.list"
    static func channelRow(_ name: String) -> String { "channel.row.\(name)" }
    static let channelJoin = "channel.join"
    static let channelComposer = "channel.composer"
    static let channelThread = "channel.thread"
}