struct AdaptStreamState {
    var toolCallIndex: Int = 0
    var hasToolCalls: Bool = false
    var hasEmittedContentDeltas: Bool = false
    var emittedRole: Bool = false
    var eventCount: Int = 0
    var emittedChunkCount: Int = 0
}
