import 'package:flutter/material.dart';

import '../../core/network_error_handler.dart';
import '../../widgets/app_toast.dart';
import '../home/user_profile.dart' as home;
import '../settings/settings_state.dart';
import 'api_auth_service.dart';
import 'auth_service.dart';
import 'auth_storage.dart';
import 'models/auth_session.dart';
import 'models/user_profile.dart';
// home/user_profile.dart re-exports Gender, but biz auth/UserProfile bilan ham ishlaymiz.
import 'screens/otp_step.dart';
import 'screens/phone_step.dart';
import 'screens/profile_step.dart';

enum _AuthStep { phone, otp, profile }

class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    super.key,
    required this.onAuthenticated,
    required this.onSkip,
    this.service,
    this.storage = const AuthStorage(),
  });

  final VoidCallback onAuthenticated;
  final VoidCallback onSkip;
  final AuthService? service;
  final AuthStorage storage;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  late final AuthService _service;
  _AuthStep _step = _AuthStep.phone;
  String _phone = '';
  String? _token;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ApiAuthService();
  }

  Future<void> _handlePhoneSubmit(String phone) async {
    setState(() {
      _submitting = true;
      _phone = phone;
    });
    try {
      await _service.sendOtp(phone);
      if (!mounted) return;
      setState(() {
        _step = _AuthStep.otp;
        _submitting = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final shown = await NetworkErrorHandler.maybeShow(
        context,
        e,
        onRetry: () => _handlePhoneSubmit(phone),
      );
      if (!mounted) return;
      if (shown) return;
      AppToast.error(context, e.message);
    }
  }

  Future<void> _handleVerified(VerifyResult result) async {
    _token = result.token;
    await widget.storage.saveSession(
      AuthSession(
        token: result.token,
        phone: _phone,
        refreshToken: result.refreshToken,
      ),
    );
    if (!mounted) return;
    AppToast.success(context, switch (localeNotifier.value.languageCode) {
      'ru' => 'Введённый код подтверждения верный!',
      'en' => 'The verification code you entered is correct!',
      _ => "Siz kiritgan tasdiqlash kodi to'g'ri kiritildi!",
    });
    if (result.isNewUser) {
      setState(() => _step = _AuthStep.profile);
    } else {
      // Mavjud foydalanuvchi — backend'dan profilni olib mahalliy saqlash.
      try {
        final remote = await _service.fetchProfile(result.token);
        if (remote.fullName.isNotEmpty) {
          await widget.storage.saveProfile(remote);
          home.userProfileNotifier.value = home.UserProfile(
            name: remote.fullName,
            phone: '+$_phone',
            dateOfBirth: remote.dateOfBirth,
            gender: remote.gender,
          );
        }
      } catch (_) {
        // Network xatosi bo'lsa, mahalliy saqlangan bo'lsa shuni olamiz.
        final saved = await widget.storage.loadProfile();
        if (saved.fullName.isNotEmpty) {
          home.userProfileNotifier.value = home.UserProfile(
            name: saved.fullName,
            phone: '+$_phone',
            dateOfBirth: saved.dateOfBirth,
            gender: saved.gender,
          );
        }
      }
      if (!mounted) return;
      widget.onAuthenticated();
    }
  }

  Future<void> _handleProfileSubmit(UserProfile profile) async {
    setState(() => _submitting = true);
    try {
      if (_token != null) {
        await _service.completeProfile(_token!, profile);
      }
      await widget.storage.saveProfile(profile);
      home.userProfileNotifier.value = home.UserProfile(
        name: profile.fullName,
        phone: '+$_phone',
        dateOfBirth: profile.dateOfBirth,
        gender: profile.gender,
      );
      if (!mounted) return;
      widget.onAuthenticated();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final shown = await NetworkErrorHandler.maybeShow(
        context,
        e,
        onRetry: () => _handleProfileSubmit(profile),
      );
      if (!mounted) return;
      if (shown) return;
      AppToast.error(context, e.message);
    }
  }

  void _handleEditPhone() {
    setState(() => _step = _AuthStep.phone);
  }

  Future<void> _handleSkip() async {
    await widget.storage.clear();
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final current = switch (_step) {
      _AuthStep.phone => PhoneStep(
        key: const ValueKey('step.phone'),
        initialDigits: _phone.length == 12 ? _phone.substring(3) : '',
        loading: _submitting,
        onSubmit: _handlePhoneSubmit,
        onSkip: _handleSkip,
      ),
      _AuthStep.otp => OtpStep(
        key: const ValueKey('step.otp'),
        phone: _phone,
        service: _service,
        onVerified: _handleVerified,
        onEdit: _handleEditPhone,
        onSkip: _handleSkip,
      ),
      _AuthStep.profile => ProfileStep(
        key: const ValueKey('step.profile'),
        loading: _submitting,
        onSubmit: _handleProfileSubmit,
        onBack: () => setState(() => _step = _AuthStep.otp),
        onSkip: () async {
          // Skipping profile keeps session (authenticated as guest profile).
          widget.onAuthenticated();
        },
      ),
    };

    return PopScope(
      canPop: _step == _AuthStep.phone,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step == _AuthStep.otp) {
          setState(() => _step = _AuthStep.phone);
        } else if (_step == _AuthStep.profile) {
          setState(() => _step = _AuthStep.otp);
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: current,
      ),
    );
  }
}
