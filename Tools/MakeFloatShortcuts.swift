import Foundation

// The AppIntentDescriptor and image token shape were captured from a real
// Float With Cod workflow created in Shortcuts on the iOS 26.5 simulator.
// Generate unsigned files, then use Apple's `shortcuts sign --mode anyone`.
// No image, clipboard contents, credentials or personal contact info included.
guard (4...5).contains(CommandLine.arguments.count) else {
    fatalError("Usage: swift Tools/MakeFloatShortcuts.swift bundle-id app-name output-directory [team-id]")
}
let bundleID = CommandLine.arguments[1]
let appName = CommandLine.arguments[2]
let teamID = CommandLine.arguments.count == 5 ? CommandLine.arguments[4] : "UE492DNA6V"
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func floatAction(input: [String: Any]) -> [String: Any] {
    [
        "WFWorkflowActionIdentifier": "\(bundleID).FloatWithCodIntent",
        "WFWorkflowActionParameters": [
            "AppIntentDescriptor": [
                "AppIntentIdentifier": "FloatWithCodIntent",
                "BundleIdentifier": bundleID,
                "Name": appName,
                "TeamIdentifier": teamID,
            ],
            "image": ["Value": input, "WFSerializationType": "WFTextTokenAttachment"],
            "UUID": UUID().uuidString,
        ],
    ]
}
let identity = ["BundleIdentifier": bundleID, "TeamIdentifier": teamID]
let identityData = try PropertyListSerialization.data(fromPropertyList: identity, format: .xml, options: 0)
try identityData.write(to: output.appendingPathComponent("InstallerInfo.plist"), options: .atomic)

let captureID = UUID().uuidString
let templates: [(String, [[String: Any]], Bool)] = [
    ("Float with Cod", [floatAction(input: ["Type": "ExtensionInput"])], true),
    ("Screenshot and Float with Cod", [
        ["WFWorkflowActionIdentifier": "is.workflow.actions.takescreenshot",
         "WFWorkflowActionParameters": ["UUID": captureID]],
        floatAction(input: ["Type": "ActionOutput", "OutputUUID": captureID, "OutputName": "Screenshot"]),
    ], false),
]
for (name, actions, shareSheet) in templates {
    var workflow: [String: Any] = [
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "4610",
        "WFWorkflowMinimumClientVersion": 1113,
        "WFWorkflowMinimumClientVersionString": "1113",
        "WFWorkflowIcon": ["WFWorkflowIconGlyphNumber": 59511, "WFWorkflowIconStartColor": 4274264319],
        "WFWorkflowActions": actions,
        "WFWorkflowTypes": shareSheet ? ["ActionExtension"] : [],
        "WFWorkflowInputContentItemClasses": shareSheet ? ["WFImageContentItem"] : [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowImportQuestions": [],
    ]
    // A capture Shortcut intentionally starts without external input. Applying
    // Stop and Respond to it cancels before Take Screenshot can even run.
    if shareSheet {
        workflow["WFWorkflowNoInputBehavior"] = ["Name": "WFWorkflowNoInputBehaviorShowError", "Parameters": [:]]
    }
    let data = try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
    let url = output.appendingPathComponent(name).appendingPathExtension("shortcut")
    try data.write(to: url, options: .atomic)
    print(url.path)
}
