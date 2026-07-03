import Foundation
import PildoraDrugIndex

// Build-time generator for the bundled **core** drug index.
//
// Usage: pildora-core-index-tool <seed.json> <output.db>
//
// Reads a checked-in `DrugIndexSeed` JSON and writes a schema-identical SQLite
// index that the iOS app bundles as its offline core tier. Kept tiny and
// dependency-free so it can run from an Xcode pre-build script phase.

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data(
        "usage: \(args.first ?? "pildora-core-index-tool") <seed.json> <output.db>\n".utf8
    ))
    exit(2)
}

let seedURL = URL(fileURLWithPath: args[1])
let outputPath = args[2]

do {
    try SeedIndexBuilder.build(fromSeedAt: seedURL, to: outputPath)
    let seed = try SeedIndexBuilder.loadSeed(from: seedURL)
    FileHandle.standardError.write(Data(
        ("pildora-core-index-tool: wrote \(outputPath) "
        + "(\(seed.drugs.count) drugs, \(seed.supplements.count) supplements)\n").utf8
    ))
} catch {
    FileHandle.standardError.write(Data("pildora-core-index-tool: \(error)\n".utf8))
    exit(1)
}
