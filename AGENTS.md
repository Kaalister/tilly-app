<claude-mem-context>
# Memory Context

# [tilly-app] recent context, 2026-09-11 10:30am GMT+2

## Session Summary
Created 10 specialized agents for the Tilly project based on the transfer documentation and codebase analysis. Agents are stored in `.opencode/agent/` and cover all key areas of the Flutter multi-platform cash register app.

## Agents Created

| Agent | Role | Key Focus |
|-------|------|-----------|
| `senior-flutter` | Senior Flutter Engineer | Architecture, state, cross-platform, CI, testing |
| `senior-android` | Senior Android Expert | APK signing, keystore, Firebase monitoring, device testing |
| `senior-ios` | Senior iOS/macOS Expert | macOS DMG, unsigned distribution, future iOS/PWA |
| `firebase-engineer` | Firebase Specialist | Sync (Auth/Firestore), monitoring (Crashlytics), config parsing |
| `data-engineer` | Data & Storage Engineer | SQLite schema v1→v8, migrations, backup/restore, stock tracking |
| `ui-ux-engineer` | UI/UX Engineer | Responsive layouts, Tiko tutorial, mobile cart+keyboard, Material theming |
| `platform-integration-engineer` | Platform Integration | HelloAsso, PDF exports, GitHub updates, tilly-platform prep |
| `release-engineer` | Release Engineer | GitHub Actions, versioning, artifacts, signing secrets |
| `qa-engineer` | QA/Test Engineer | Test strategy, CI alignment (3.41.8 vs 3.47.0), device matrix |
| `secretary` | Documentation Steward | AGENTS.md, TODO, README, user guides - auto-updates |
| `reviewer` | Code Reviewer | Read-only reviews, blocks push on violations |
| `tech-writer` | Technical Writer | User docs for non-technical associations |

## Current Priority 0 Blockers (from transfer doc)
1. **CI failures**: Flutter 3.47.0 breaks 8 tests - `ListTile` under `DecoratedBox`/`ColoredBox` assertion
2. **Version drift**: `pubspec.yaml` = `1.0.0+1` vs last release `v1.1.4`
3. **README repo mismatch**: Points to `Kaalister/Tilly-caisse-app` but actual is `Kaalister/Frag-addict-caisse-app`
4. **No macOS artifacts** in last release `v1.1.4`

## Next Actions
- Senior-flutter + QA-engineer: Fix ListTile/Material assertions for Flutter 3.47.0
- Release-engineer: Align versioning, fix README links
- Secretary: Update TODO_DOCUMENTATION_ET_EVOLUTIONS.md with agent assignments
- Reviewer: Gate all pushes until CI green

## Key Files Reference
- `lib/main.dart` - Platform DB init
- `lib/src/controllers/app_controller.dart` - Central logic
- `lib/src/data/local_database.dart` - SQLite v8, migrations, backup
- `lib/src/services/firebase_sync_service.dart` - Manual snapshot sync
- `lib/src/ui/pages/sales_page.dart` - Mobile cart (critical UX)
- `test/widget_test.dart` - 41 tests including cart regression
- `.github/workflows/windows-release.yml` - 3-platform CI/CD
- `documentation/MISE_EN_PLACE.md` - User guide (needs non-tech test)
</claude-mem-context>