#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

default_tests=(GatewayInfoReader DNSServiceResolver GzipDecompressor WindowCoordinator SettingsViewModel LogFileWriter MihomoKernelPath DNSProgressAnimation MihomoTerminationWaitState IPDataSourceAggregation IPQuery DNSSceneApplication ScenePersistence AsyncDNSOperations MihomoProcessIdentity StreamingDetection MihomoDownloadProgress AppControl SceneApplicationSelection)

if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' \
    'Usage: bash Scripts/run-swift-regressions.sh [TEST ...]' \
    'Without arguments, runs the offline regression checks used by macOS CI.' \
    "Default tests: ${default_tests[*]}" \
    'Additional UI checks: PopoverContentLayout NetworkToolSheetSizing SheetOutsideDismissal' \
    'UI checks may create off-screen windows; they do not launch Kairos.'
  exit 0
fi

run_test() {
  local name="$1"
  local sources=()
  local compiler_flags=(-swift-version 5)
  case "$name" in
    DNSServiceResolver) sources=(KairosHelper/DNSServiceResolver.swift) ;;
    GatewayInfoReader) sources=(KairosHelper/GatewayInfoReader.swift) ;;
    GzipDecompressor) sources=(App/Services/GzipDecompressor.swift) ;;
    WindowCoordinator) sources=(App/Coordinators/WindowCoordinator.swift) ;;
    SettingsViewModel) sources=(App/Utils/L10n.swift App/Models/MihomoModels.swift App/Services/MihomoConfigService.swift App/Services/APIKeyManager.swift App/ViewModels/SettingsViewModel.swift) ;;
    LogFileWriter) sources=(App/Utils/Logging/LogLevel.swift App/Utils/Logging/LogEntry.swift App/Utils/Logging/LogStore.swift) ;;
    MihomoKernelPath) sources=(App/Utils/L10n.swift App/Models/MihomoModels.swift App/Services/MihomoFileService.swift) ;;
    DNSProgressAnimation) sources=(App/Models/DNSTestDomain.swift App/Views/Components/NetworkTools/DNSProgressBackdrop.swift) ;;
    MihomoTerminationWaitState) sources=(App/Services/MihomoTerminationWaitState.swift) ;;
    ScenePersistence) sources=(App/Utils/L10n.swift App/Utils/NetworkValidator.swift App/Utils/SceneValidation.swift App/Models/Scene.swift App/Models/DNSScene.swift App/Models/MihomoModels.swift App/Models/KairosExportData.swift App/Services/APIKeyManager.swift App/Services/MihomoConfigService.swift App/Services/SceneFileStorage.swift App/Services/SceneStorage.swift App/Services/DNSSceneStorage.swift App/Services/SettingsImportService.swift) ;;
    AsyncDNSOperations) sources=(App/Utils/L10n.swift App/Utils/AsyncTimeout.swift App/Utils/SystemDNSResolver.swift App/Utils/DNSChecker.swift) ;;
    StreamingDetection) sources=(App/Utils/L10n.swift App/Utils/URLRequest+Extensions.swift App/Models/IPQualityModels.swift App/Utils/AsyncTimeout.swift App/Utils/SystemDNSResolver.swift App/Utils/DNSChecker.swift App/UseCases/IPQuality/StreamingTestUseCase.swift) ;;
    AppControl) sources=(App/Models/Scene.swift App/Services/NetworkMonitor/AppControlState.swift App/Services/NetworkMonitor/AppControlService.swift App/Services/NetworkMonitor/SceneMatchingEngine.swift App/Services/MihomoTerminationWaitState.swift) ;;
    MihomoDownloadProgress) sources=(App/Services/MihomoDownloadProgressDelegate.swift App/Services/MihomoDownloadService.swift App/Services/GzipDecompressor.swift App/Utils/L10n.swift) ;;
    SceneApplicationSelection) sources=(App/Models/Scene.swift App/Services/NetworkMonitor/AppControlState.swift App/Services/NetworkMonitor/AppControlService.swift App/Services/MihomoTerminationWaitState.swift App/Views/Components/AppControlPresentation.swift) ;;
    MihomoProcessIdentity) sources=(App/Utils/L10n.swift App/Models/MihomoModels.swift App/Services/MihomoTerminationWaitState.swift App/Services/MihomoProcessService.swift) ;;
    DNSSceneApplication) sources=(App/Models/DNSScene.swift App/Services/NetworkMonitor/DNSSceneMatchingEngine.swift App/Services/NetworkMonitor/DNSSceneApplicationState.swift App/Services/DNSResolverConfiguration.swift) ;;
    IPQuery) sources=(App/Utils/L10n.swift App/Utils/GeoUtils.swift App/Utils/NetworkValidator.swift App/Utils/URLRequest+Extensions.swift App/Models/IPQueryModels.swift App/Services/APIKeyManager.swift App/Services/IPAPIRateLimit.swift App/Services/IPQueryService.swift App/Models/IPQualityModels.swift App/Services/IPDataSourceService.swift App/Services/IPDataSourceService+Parsers.swift) ;;
    IPDataSourceAggregation) sources=(App/Models/IPQualityModels.swift App/Services/APIKeyManager.swift App/Services/IPAPIRateLimit.swift App/Services/IPDataSourceService.swift App/Services/IPDataSourceService+Parsers.swift App/UseCases/IPQuality/MultiSourceAggregationUseCase.swift) ;;
    PopoverContentLayout) sources=(App/Coordinators/WindowCoordinator.swift App/Coordinators/PopoverContentViewController.swift) ;;
    NetworkToolSheetSizing) sources=(App/Views/Components/PopoverDetailPage.swift App/Extensions/View+ScrollView.swift App/Views/Components/NetworkTools/NetworkToolSheet.swift App/Views/Components/SheetHeader.swift App/Views/Components/NetworkTools/DNSProgressBackdrop.swift App/Views/Components/ActionTextField.swift App/Extensions/View+TextInput.swift) ;;
    SheetOutsideDismissal) sources=(App/Extensions/View+SheetDismissal.swift) ;;
    *) printf 'Unknown regression check: %s\n' "$name" >&2; return 1 ;;
  esac

  if [[ "$name" == "MihomoProcessIdentity" || "$name" == "AppControl" || "$name" == "SceneApplicationSelection" ]]; then
    compiler_flags+=(-default-isolation MainActor)
  fi

  printf 'Running %s regression checks\n' "$name"
  xcrun swiftc "${compiler_flags[@]}" -target arm64-apple-macos26.0 -parse-as-library \
    "${sources[@]}" "Scripts/Tests/${name}Tests.swift" -o "build/Tests/${name}Tests"
  "build/Tests/${name}Tests"
  if [[ "$name" == "NetworkToolSheetSizing" ]]; then
    # Process-local preference override; do not change the user's scrollbar setting.
    "build/Tests/${name}Tests" -AppleShowScrollBars Always
  fi
}

mkdir -p build/Tests
if [[ "$#" -eq 0 ]]; then
  set -- "${default_tests[@]}"
fi
for test_name in "$@"; do
  run_test "$test_name"
done
