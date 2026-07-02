import 'package:flutter/material.dart';

import '../auth/auth_storage.dart';
import 'api_ai_valuation_job_service.dart';
import 'models/ai_baholash_bundle.dart';
import 'screens/ai_area_screen.dart';
import 'screens/ai_cadastre_screen.dart';
import 'screens/ai_client_form_screen.dart';
import 'screens/ai_intake_screen.dart';
import 'screens/ai_location_screen.dart';
import 'screens/ai_purpose_screen.dart';

/// Saqlangan qadam nomidan mos wizard ekranini quradi (skan qadamidan keyingi
/// qadamlar). `scanJobId` — skan bor bo'lsa, cadastre qadamida "3D modelni
/// ko'rish" tugmasi chiqadi.
///
/// "Mening arizalarim" va "Arizalar" ro'yxati shu bitta funksiyani ishlatadi —
/// resume mantig'i bir joyda.
Widget aiStepScreen(AiBaholashBundle bundle, String? step, int? scanJobId) {
  switch (step) {
    case 'area':
      return AiAreaScreen(
        scan: bundle.scan,
        draftId: bundle.draftId,
        scanJobId: scanJobId,
      );
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
      );
  }
}

/// DRAFT AI Baholash arizasini saqlangan qadamdan davom ettiradi: snapshot'ni
/// oladi, bundle quradi va mos qadam ekranini ochadi. Skan bor bo'lsa, cadastre
/// qadamida "3D modelni ko'rish" tugmasi chiqadi.
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
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => aiStepScreen(bundle, snap.currentStep, scanJobId),
    ),
  );
}
