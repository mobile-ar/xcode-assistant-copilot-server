@testable import XcodeAssistantCopilotServer
import Testing

@Suite("TabIdentifierResolver")
struct TabIdentifierResolverTests {

    let singleWindowError = """
    Error: Valid tabIdentifier required. Choose from the following open windows:
    * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/MyApp/MyApp.xcodeproj
    """

    let multiWindowError = """
    Error: Valid tabIdentifier required. Choose from the following open windows:
    * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/Sumatron2/Sumatron2.xcodeproj
    * tabIdentifier: windowtab2, workspacePath: /Users/dev/Projects/spark-app-ios/Spark.xcworkspace
    """

    @Test func isTabIdentifierErrorReturnsTrueForValidErrorPrefix() {
        #expect(TabIdentifierResolver.isTabIdentifierError("Error: Valid tabIdentifier required. Choose from the following open windows:"))
    }

    @Test func isTabIdentifierErrorReturnsTrueForFullErrorText() {
        #expect(TabIdentifierResolver.isTabIdentifierError(singleWindowError))
    }

    @Test func isTabIdentifierErrorReturnsFalseForUnrelatedError() {
        #expect(!TabIdentifierResolver.isTabIdentifierError("Error: File not found"))
    }

    @Test func isTabIdentifierErrorReturnsFalseForEmptyString() {
        #expect(!TabIdentifierResolver.isTabIdentifierError(""))
    }

    @Test func isTabIdentifierErrorReturnsFalseForSuccessText() {
        #expect(!TabIdentifierResolver.isTabIdentifierError("File updated successfully"))
    }

    @Test func resolveReturnsFallbackTabWhenNoFilePathProvided() {
        let result = TabIdentifierResolver.resolve(from: singleWindowError, filePath: nil)
        #expect(result == "windowtab1")
    }

    @Test func resolveReturnsFallbackTabWhenFilePathIsEmpty() {
        let result = TabIdentifierResolver.resolve(from: singleWindowError, filePath: "")
        #expect(result == "windowtab1")
    }

    @Test func resolveReturnsFallbackTabWhenFilePathMatchesNoWorkspace() {
        let result = TabIdentifierResolver.resolve(from: multiWindowError, filePath: "/Users/dev/Projects/OtherApp/SomeFile.swift")
        #expect(result == "windowtab1")
    }

    @Test func resolveMatchesFirstTabWhenFilePathBelongsToFirstWorkspace() {
        let filePath = "/Users/dev/Projects/Sumatron2/Sumatron2/Screens/Profile/UserSummaryView.swift"
        let result = TabIdentifierResolver.resolve(from: multiWindowError, filePath: filePath)
        #expect(result == "windowtab1")
    }

    @Test func resolveMatchesSecondTabWhenFilePathBelongsToSecondWorkspace() {
        let filePath = "/Users/dev/Projects/spark-app-ios/Spark/Views/HomeView.swift"
        let result = TabIdentifierResolver.resolve(from: multiWindowError, filePath: filePath)
        #expect(result == "windowtab2")
    }

    @Test func resolvePicksBestMatchWhenMultipleWorkspacePathsOverlap() {
        let overlappingError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/MyApp/MyApp.xcodeproj
        * tabIdentifier: windowtab2, workspacePath: /Users/dev/Projects/MyApp/MyApp/SubModule/SubModule.xcodeproj
        """
        let filePath = "/Users/dev/Projects/MyApp/MyApp/SubModule/Sources/SomeFile.swift"
        let result = TabIdentifierResolver.resolve(from: overlappingError, filePath: filePath)
        #expect(result == "windowtab2")
    }

    @Test func resolveReturnsNilWhenErrorTextHasNoWindowEntries() {
        let result = TabIdentifierResolver.resolve(from: "Error: Valid tabIdentifier required.", filePath: nil)
        #expect(result == nil)
    }

    @Test func resolveReturnsNilForNonErrorText() {
        let result = TabIdentifierResolver.resolve(from: "Success", filePath: nil)
        #expect(result == nil)
    }

    @Test func resolveHandlesXcworkspaceExtension() {
        let xcworkspaceError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab3, workspacePath: /Users/dev/Projects/Spark/Spark.xcworkspace
        """
        let filePath = "/Users/dev/Projects/Spark/Spark/Sources/AppDelegate.swift"
        let result = TabIdentifierResolver.resolve(from: xcworkspaceError, filePath: filePath)
        #expect(result == "windowtab3")
    }

    @Test func resolveHandlesSingleWindowWithMatchingFilePath() {
        let filePath = "/Users/dev/Projects/MyApp/MyApp/ContentView.swift"
        let result = TabIdentifierResolver.resolve(from: singleWindowError, filePath: filePath)
        #expect(result == "windowtab1")
    }
}