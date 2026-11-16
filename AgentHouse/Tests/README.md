# Tests

Unit tests for the Core layer (HookEvent decoding, EventServer, HookInstaller,
SessionStateMachine, SessionManager, UsageReader, LimitDetector) plus a few
preference stores. Run them with:

```bash
xcodebuild -project AgentHouse.xcodeproj -scheme AgentHouse -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```
