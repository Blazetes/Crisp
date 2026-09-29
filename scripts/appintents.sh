# Sourced by dev.sh and release.sh. Shortcuts finds Crisp's actions
# (Crisp/App/ShortcutsActions.swift) through Contents/Resources/Metadata.appintents,
# which an Xcode build writes with appintentsmetadataprocessor. Crisp builds with
# plain swiftc, so these helpers do the same two steps: swiftc emits the const values
# of the App Intents types, and the processor turns them into the metadata. Both
# tools must come from Xcode: the Command Line Tools have no processor, and their
# swiftc cannot expand SwiftUI's macros while it extracts const values.

# Finds Xcode and writes the protocol list swiftc gathers const values for (the
# list Xcode itself passes). Returns 1 without Xcode; the caller then builds as before.
appintents_init() {
    AI_WORK="$1"
    AI_DEV=""
    for dir in "${DEVELOPER_DIR:-}" "$(xcode-select -p 2>/dev/null)" /Applications/Xcode.app/Contents/Developer; do
        if [ -n "$dir" ] && DEVELOPER_DIR="$dir" xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
            AI_DEV="$dir"
            break
        fi
    done
    [ -n "$AI_DEV" ] || return 1
    mkdir -p "$AI_WORK"
    cat > "$AI_WORK/protocols.json" <<'EOF'
["AnyResolverProviding","AppEntity","AppEnum","AppExtension","AppIntent","AppIntentsPackage","AppShortcutProviding","AppShortcutsProvider","AppUnionValue","AppUnionValueCasesProviding","DynamicOptionsProvider","EntityQuery","ExtensionPointDefining","IntentValueQuery","Resolver","TransientEntity","_AssistantIntentsProvider","_GenerativeFunctionExtractable","_IntentValueRepresentable"]
EOF
}

# Extra swiftc flags for one architecture: whole-module, so one const values file.
appintents_swiftc_flags() {
    echo "-wmo -emit-const-values-path $AI_WORK/Crisp-$1.swiftconstvalues -Xfrontend -const-gather-protocols-file -Xfrontend $AI_WORK/protocols.json"
}

# Writes Metadata.appintents into <resources> for <binary>, built for the given
# architectures with appintents_swiftc_flags. The module is "main": swiftc names it
# after the -o file, and neither Crisp-bin nor Crisp-arm64 is a valid module name.
appintents_metadata() {
    local binary="$1" resources="$2"
    shift 2
    local args=()
    : > "$AI_WORK/empty.list"
    find "$ROOT/Crisp" -name '*.swift' > "$AI_WORK/sources.list"
    for a in "$@"; do
        echo "$AI_WORK/Crisp-$a.swiftconstvalues" > "$AI_WORK/constvals-$a.list"
        args+=(--target-triple "$a-apple-macos14.0" --swift-const-vals-list "$AI_WORK/constvals-$a.list")
    done
    rm -rf "$resources/Metadata.appintents"
    DEVELOPER_DIR="$AI_DEV" xcrun appintentsmetadataprocessor \
        --toolchain-dir "$AI_DEV/Toolchains/XcodeDefault.xctoolchain" --module-name main \
        --sdk-root "$(DEVELOPER_DIR="$AI_DEV" xcrun --show-sdk-path)" \
        --xcode-version "$(DEVELOPER_DIR="$AI_DEV" xcodebuild -version | awk '/Build version/ {print $3}')" \
        --platform-family macOS --deployment-target 14.0 --bundle-identifier com.crisp.app \
        --output "$resources" --binary-file "$binary" "${args[@]}" \
        --source-file-list "$AI_WORK/sources.list" \
        --metadata-file-list "$AI_WORK/empty.list" --static-metadata-file-list "$AI_WORK/empty.list" \
        --compile-time-extraction --deployment-aware-processing --validate-assistant-intents \
        --no-app-shortcuts-localization 2>&1 | grep -v -e "Starting appintentsmetadataprocessor" -e "Writing Metadata" -e "Metadata root" || true
    [ -f "$resources/Metadata.appintents/extract.actionsdata" ]
}
