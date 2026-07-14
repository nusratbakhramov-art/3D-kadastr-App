import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_toast.dart';
import '../auth/api_auth_service.dart';
import '../auth/auth_service.dart';
import '../auth/auth_storage.dart';
import '../auth/models/user_profile.dart' as auth;
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../auth/widgets/dob_field.dart';
import '../auth/widgets/gender_toggle.dart';
import '../home/user_profile.dart';
import '../settings/settings_state.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    this.authService,
    this.authStorage = const AuthStorage(),
  });

  final AuthService? authService;
  final AuthStorage authStorage;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<MyProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _nameCtrl;
  late final AuthService _service;
  String? _draftAvatarPath;
  DateTime? _draftDob;
  Gender? _draftGender;

  @override
  int get currentToken => 1;

  @override
  void initState() {
    super.initState();
    _service = widget.authService ?? ApiAuthService();
    final p = userProfileNotifier.value;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _draftAvatarPath = p?.avatarPath;
    _draftDob = p?.dateOfBirth;
    _draftGender = p?.gender;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _resetDraftFromProfile() {
    final p = userProfileNotifier.value;
    _nameCtrl.text = p?.name ?? '';
    _draftAvatarPath = p?.avatarPath;
    _draftDob = p?.dateOfBirth;
    _draftGender = p?.gender;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _draftAvatarPath = picked.path);
    }
  }

  Future<void> _save(Locale locale) async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, _S.errorEmptyName(locale));
      return;
    }
    if (_draftDob == null || _draftGender == null) {
      AppToast.error(context, _S.errorIncomplete(locale));
      return;
    }

    setState(() => _saving = true);
    try {
      final session = await widget.authStorage.loadSession();
      if (session.token == null) {
        if (!mounted) return;
        AppToast.error(context, _S.errorUnauthenticated(locale));
        setState(() => _saving = false);
        return;
      }

      final apiProfile = auth.UserProfile(
        fullName: name,
        dateOfBirth: _draftDob,
        gender: _draftGender,
      );
      await _service.completeProfile(session.token!, apiProfile);
      await widget.authStorage.saveProfile(apiProfile);

      if (!mounted) return;
      final current = userProfileNotifier.value;
      userProfileNotifier.value = (current ?? const UserProfile(name: ''))
          .copyWith(
            name: name,
            avatarPath: _draftAvatarPath,
            dateOfBirth: _draftDob,
            gender: _draftGender,
          );
      setState(() {
        _editing = false;
        _saving = false;
      });
      AppToast.success(context, _S.saved(locale));
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, _S.errorNetwork(locale));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<UserProfile?>(
          valueListenable: userProfileNotifier,
          builder: (context, profile, _) {
            return Scaffold(
              backgroundColor: ColorTokens.scaffoldBg(context),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const AppGlowBackground(),
                  SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.0,
                              0.4,
                              curve: Curves.easeOutCubic,
                            ),
                            child: AppHeaderBack(
                              title: _S.title(locale),
                              trailing: _EditToggle(
                                editing: _editing,
                                saving: _saving,
                                editLabel: _S.edit(locale),
                                saveLabel: _S.save(locale),
                                onEdit: () {
                                  _resetDraftFromProfile();
                                  setState(() => _editing = true);
                                },
                                onSave: () => _save(locale),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.1,
                              0.6,
                              curve: Curves.easeOutCubic,
                            ),
                            child: Center(
                              child: _AvatarBlock(
                                editing: _editing,
                                path: _editing
                                    ? _draftAvatarPath
                                    : profile?.avatarPath,
                                name: profile?.name ?? '',
                                onTap: _pickAvatar,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.2,
                              0.85,
                              curve: Curves.easeOutCubic,
                            ),
                            child: _editing
                                ? _editFields(context, locale, profile)
                                : _viewCard(locale, profile),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _viewCard(Locale locale, UserProfile? profile) {
    return AppMenuCard(
      rows: [
        _ReadOnlyRow(
          icon: Icons.person_outline_rounded,
          label: _S.fullName(locale),
          value: profile?.name.isNotEmpty == true
              ? profile!.name
              : _S.empty(locale),
        ),
        _ReadOnlyRow(
          icon: Icons.phone_iphone_rounded,
          label: _S.phone(locale),
          value: profile?.phone ?? _S.empty(locale),
        ),
        _ReadOnlyRow(
          icon: Icons.cake_outlined,
          label: _S.dob(locale),
          value: profile?.dateOfBirth != null
              ? _formatDate(profile!.dateOfBirth!)
              : _S.empty(locale),
        ),
        _ReadOnlyRow(
          icon: Icons.wc_outlined,
          label: _S.gender(locale),
          value: _genderLabel(locale, profile?.gender) ?? _S.empty(locale),
        ),
      ],
    );
  }

  Widget _editFields(
    BuildContext context,
    Locale locale,
    UserProfile? profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: _S.fullName(locale)),
        const SizedBox(height: 6),
        _NameField(controller: _nameCtrl, hint: _S.fullName(locale)),
        const SizedBox(height: 14),
        _FieldLabel(text: _S.phone(locale)),
        const SizedBox(height: 6),
        _LockedField(
          text: profile?.phone ?? '',
          hint: '+998',
          trailing: const Icon(Icons.lock_outline_rounded, size: 18),
        ),
        const SizedBox(height: 14),
        _FieldLabel(text: _S.dob(locale)),
        const SizedBox(height: 6),
        DobField(
          value: _draftDob,
          onChanged: (v) => setState(() => _draftDob = v),
        ),
        const SizedBox(height: 14),
        _FieldLabel(text: _S.gender(locale)),
        const SizedBox(height: 6),
        GenderToggle(
          value: _draftGender,
          onChanged: (g) => setState(() => _draftGender = g),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String? _genderLabel(Locale l, Gender? g) {
    if (g == null) return null;
    switch (g) {
      case Gender.male:
        return switch (l.languageCode) {
          'ru' => 'Мужской',
          'en' => 'Male',
          _ => 'Erkak',
        };
      case Gender.female:
        return switch (l.languageCode) {
          'ru' => 'Женский',
          'en' => 'Female',
          _ => 'Ayol',
        };
    }
  }
}

class _EditToggle extends StatelessWidget {
  const _EditToggle({
    required this.editing,
    required this.saving,
    required this.editLabel,
    required this.saveLabel,
    required this.onEdit,
    required this.onSave,
  });

  final bool editing;
  final bool saving;
  final String editLabel;
  final String saveLabel;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = editing ? saveLabel : editLabel;
    final borderRadius = BorderRadius.circular(20);
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: borderRadius,
      child: InkWell(
        onTap: hapticTap(saving ? null : (editing ? onSave : onEdit)),
        borderRadius: borderRadius,
        child: Tooltip(
          message: semanticsLabel,
          child: Semantics(
            label: semanticsLabel,
            button: true,
            child: editing
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.brandGreen,
                              ),
                            ),
                          )
                        : Text(
                            saveLabel,
                            style: const TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.brandGreen,
                            ),
                          ),
                  )
                : SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/pen-square.svg',
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(
                          ColorTokens.primaryText(context),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.editing,
    required this.path,
    required this.name,
    required this.onTap,
  });

  final bool editing;
  final String? path;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppAvatar(path: path, name: name, size: 110),
        if (editing)
          Positioned(
            right: -2,
            bottom: -2,
            child: Material(
              color: AppColors.brandGreen,
              shape: CircleBorder(
                side: BorderSide(
                  color: ColorTokens.scaffoldBg(context),
                  width: 3,
                ),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: hapticTap(onTap),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ColorTokens.iconBg(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: ColorTokens.secondaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: ColorTokens.primaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: ColorTokens.secondaryText(context),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.inputFill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorTokens.outline(context)),
      ),
      child: TextField(
        controller: controller,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        textCapitalization: TextCapitalization.words,
        style: TextStyle(
          color: ColorTokens.primaryText(context),
          fontFamily: 'MTSCompact',
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: ColorTokens.tertiaryText(context),
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w400,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({
    required this.text,
    required this.hint,
    required this.trailing,
  });

  final String text;
  final String hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final showHint = text.isEmpty;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ColorTokens.inputFill(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorTokens.outline(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              showHint ? hint : text,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: showHint
                    ? ColorTokens.tertiaryText(context)
                    : ColorTokens.secondaryText(context),
              ),
            ),
          ),
          IconTheme(
            data: IconThemeData(color: ColorTokens.secondaryText(context)),
            child: trailing,
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Мой профиль',
    'en' => 'My profile',
    _ => 'Mening profilim',
  };
  static String edit(Locale l) => switch (l.languageCode) {
    'ru' => 'Изменить',
    'en' => 'Edit',
    _ => 'Tahrirlash',
  };
  static String save(Locale l) => switch (l.languageCode) {
    'ru' => 'Сохранить',
    'en' => 'Save',
    _ => 'Saqlash',
  };
  static String fullName(Locale l) => switch (l.languageCode) {
    'ru' => 'Имя и фамилия',
    'en' => 'Full name',
    _ => 'F.I.O.',
  };
  static String phone(Locale l) => switch (l.languageCode) {
    'ru' => 'Телефон',
    'en' => 'Phone',
    _ => 'Telefon',
  };
  static String dob(Locale l) => switch (l.languageCode) {
    'ru' => 'Дата рождения',
    'en' => 'Date of birth',
    _ => 'Tug‘ilgan sana',
  };
  static String gender(Locale l) => switch (l.languageCode) {
    'ru' => 'Пол',
    'en' => 'Gender',
    _ => 'Jinsi',
  };
  static String empty(Locale l) => switch (l.languageCode) {
    'ru' => '—',
    'en' => '—',
    _ => '—',
  };
  static String saved(Locale l) => switch (l.languageCode) {
    'ru' => 'Профиль сохранён',
    'en' => 'Profile saved',
    _ => 'Profil saqlandi',
  };
  static String errorEmptyName(Locale l) => switch (l.languageCode) {
    'ru' => 'Имя не может быть пустым',
    'en' => 'Name cannot be empty',
    _ => 'Ism bo‘sh bo‘lishi mumkin emas',
  };
  static String errorIncomplete(Locale l) => switch (l.languageCode) {
    'ru' => 'Заполните все поля',
    'en' => 'Please fill in all fields',
    _ => 'Barcha maydonlarni to‘ldiring',
  };
  static String errorUnauthenticated(Locale l) => switch (l.languageCode) {
    'ru' => 'Сессия истекла, войдите снова',
    'en' => 'Session expired, please sign in again',
    _ => 'Sessiya tugagan, qayta kirib oling',
  };
  static String errorNetwork(Locale l) => switch (l.languageCode) {
    'ru' => 'Ошибка сети',
    'en' => 'Network error',
    _ => 'Tarmoq xatosi',
  };
}
