import 'package:flutter/material.dart';

import '../auth/auth_storage.dart';
import 'api_ai_valuation_job_service.dart';
import 'models/ai_baholash_bundle.dart';
import 'screens/ai_cadastre_screen.dart';
import 'screens/ai_client_form_screen.dart';
import 'screens/ai_intake_screen.dart';
import 'screens/ai_location_screen.dart';
import 'screens/ai_purpose_screen.dart';
import 'screens/ai_start_screen.dart';

/// Saqlangan qadam nomidan mos wizard ekranini quradi (skan qadamidan keyingi
/// qadamlar). `scanJobId` — skan bor bo'lsa, cadastre qadamida "3D modelni
/// ko'rish" tugmasi chiqadi.
///
/// "Mening arizalarim" va "Arizalar" ro'yxati shu bitta funksiyani ishlatadi —
/// resume mantig'i bir joyda.
Widget aiStepScreen(AiBaholashBundle bundle, String? step, int? scanJobId) {
  switch (step) {
    // Xonalarni videoga olish qadami — ro'yxat ariza id bo'yicha SERVERDAN
    // tiklanadi, ya'ni ilova yopilgan bo'lsa ham tayyor modellar ko'rinadi.
    case 'video':
      return AiStartScreen(
        scan: bundle.scan,
        draftId: bundle.draftId,
        scanJobId: scanJobId,
        // Bundle ham o'tadi: video qadamidan "Davom etish" bosilganda
        // saqlangan kadastr/mijoz/joylashuv ma'lumotlari yo'qolmasin.
        resumeBundle: bundle,
      );
    // Legacy drafts saved at the removed 'area' step resume straight into the
    // cadastre step (which now owns the area, sourced from davreestr).
    case 'client':
      return AiClientFormScreen(bundle: bundle);
    case 'location':
      return AiLocationScreen(bundle: bundle);
    case 'purpose':
      return AiPurposeScreen(bundle: bundle);
    case 'intake':
    case 'payment':
      return AiIntakeScreen(bundle: bundle);
    default: // 'cadastre' yoki noma'lum — kadastr qadamidan
      return AiCadastreScreen(
        scan: bundle.scan,
        draftId: bundle.draftId,
        scanJobId: scanJobId,
        areaM2: bundle.areaM2,
        // Resume: show the saved davreestr result without re-looking-up.
        initial: bundle.kadastr,
        // Keep the full restored bundle so Back → Davom etish preserves the
        // later steps instead of rebuilding an empty one.
        resumeBundle: bundle,
      );
  }
}

/// Wizard steps, in order. On resume we stack them up to the saved step so Back
/// walks all the way to the first step (`video`) instead of exiting to
/// Arizalar. Every screen rebuilds from the saved bundle: `cadastre` shows the
/// saved davreestr result without a re-lookup (and owns the object area).
///
/// The `video` step is optional, so a draft can legitimately sit at a later
/// step with no room video attached — resume follows the saved step and does
/// not second-guess it against the 3DGS server.
const List<String> _resumableChain = [
  'video',
  'cadastre',
  'client',
  'location',
  'purpose',
  'intake',
];

/// The list of steps to push so the user lands on [currentStep] with a Back
/// stack through the earlier bundle steps. For a non-chain step (cadastre/area/
/// unknown) it's just that single screen.
List<String> _resumeStack(String? currentStep) {
  final step = currentStep == 'payment' ? 'intake' : (currentStep ?? 'cadastre');
  final idx = _resumableChain.indexOf(step);
  if (idx < 0) return [step];
  return _resumableChain.sublist(0, idx + 1);
}

/// DRAFT AI Baholash arizasini saqlangan qadamdan davom ettiradi: snapshot'ni
/// oladi, bundle quradi va mos qadamgacha bo'lgan ekranlar stekini tiklaydi
/// (Orqaga tugmasi oldingi qadamlarga o'tadi, Arizalar'ga emas). Skan bor bo'lsa,
/// cadastre qadamida "3D modelni ko'rish" tugmasi chiqadi.
Future<void> resumeAiDraft(
  BuildContext context,
  int jobId, {
  AiValuationJobService? service,
}) async {
  final session = await const AuthStorage().loadSession();
  final token = session.token;
  if (token == null || token.isEmpty) return;
  final snap =
      await (service ?? AiValuationJobService()).get(jobId, token: token);
  if (!context.mounted) return;
  final bundle =
      AiBaholashBundle.fromJson(snap.requestPayload, draftId: snap.id);
  final scanJobId =
      (snap.scanUsdzKey != null && snap.scanUsdzKey!.isNotEmpty) ? snap.id : null;

  final steps = _resumeStack(snap.currentStep);
  final nav = Navigator.of(context);
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final screen = aiStepScreen(bundle, step, scanJobId);
    final settings = RouteSettings(name: 'ai/$step');
    if (i == steps.length - 1) {
      // Target step — animate in normally.
      await nav.push(
        MaterialPageRoute<void>(settings: settings, builder: (_) => screen),
      );
    } else {
      // Earlier steps — insert instantly beneath so only the target animates;
      // they exist purely to give the target a real Back stack.
      nav.push(
        PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, _, _) => screen,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }
}
