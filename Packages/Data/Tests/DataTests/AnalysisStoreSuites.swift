import Testing

/// Every suite that opens an analysis store, run one test at a time.
///
/// The cache's migration plan holds `AnalysisSchemaV1.CachedAnalysis` and `AnalysisSchemaV2.CachedAnalysis`, two
/// models with the same entity name. SwiftData mixes them up when containers of both versions are used at the same
/// time in one process, so a save can write version 1 columns into a version 2 row and crash
/// (`NSUnknownKeyException` for `qualityScore`). The app opens one container, so only parallel tests hit this.
@Suite(.serialized)
enum AnalysisStoreSuites {}
