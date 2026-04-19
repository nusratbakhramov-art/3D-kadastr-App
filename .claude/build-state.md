# Flutter Build State

## Flutter SDK: detected at runtime
## Dart SDK: ^3.10.1
## State Mgmt: vanilla StatefulWidget + setState (no external libs)
## Routing: stage enum in _AppRoot (no go_router)
## Architecture: feature-first under lib/features/
## Codegen: none
## Lints: flutter_lints
## Platforms: android, ios (web disabled)

## Task: Build phone-based auth flow (phone → OTP → profile) matching provided designs.

## Progress
- [ ] 1. Models (UserProfile, AuthSession, Gender)
- [ ] 2. AuthStorage
- [ ] 3. FakeAuthService
- [ ] 4. AuthScaffold
- [ ] 5. PhoneInputField
- [ ] 6. OtpBoxes
- [ ] 7. ResendTimer
- [ ] 8. GenderToggle, DobField, AuthToast, PrimaryCta
- [ ] 9. PhoneStep
- [ ] 10. OtpStep
- [ ] 11. ProfileStep
- [ ] 12. AuthFlowScreen
- [ ] 13. Integrate into _AppRoot

## Decisions
- No new deps. Use vanilla setState + SharedPreferences.
- Fake OTP = 12345 for local testing.
- 5-digit OTP, 90s resend timer.
- Uzbek hardcoded strings (matching rest of app).
