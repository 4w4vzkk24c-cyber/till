import Foundation
import Testing
@testable import Till

@Suite struct ComposerStatusTests {
    @Test func errorBeatsEverything() {
        #expect(ComposerStatus.line(error: "Nope.", fetching: true, editing: true, echo: "Today 10:20 AM") == .error("Nope."))
    }

    @Test func fetchingBeatsEditingAndEcho() {
        #expect(ComposerStatus.line(error: nil, fetching: true, editing: true, echo: "x") == .fetching)
    }

    @Test func editingBeatsEcho() {
        #expect(ComposerStatus.line(error: nil, fetching: false, editing: true, echo: "x") == .editing)
    }

    @Test func echoShowsWhenNothingElseDoes() {
        #expect(ComposerStatus.line(error: nil, fetching: false, editing: false, echo: "Today 10:20 AM")
                == .echo("Today 10:20 AM"))
    }

    @Test func nothingMeansNoLine() {
        #expect(ComposerStatus.line(error: nil, fetching: false, editing: false, echo: nil) == nil)
    }
}
