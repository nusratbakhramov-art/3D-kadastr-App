/// AI Baholash DRAFT ariza saqlash yordamchilari.
///
/// Token (AuthStorage) + [AiValuationJobService]'ni o'raydi. Saqlash JIM —
/// xato/offline navigatsiyani bloklamaydi (kelajak: lokal queue + retry).
library;

import 'dart:async';

import '../auth/auth_storage.dart';
import 'api_ai_valuation_job_service.dart';
import 'models/ai_baholash_bundle.dart';

/// Skandan keyin DRAFT ariza yaratadi → draft id (login/tarmoq yo'q bo'lsa null).
Future<int?> createAiDraft({
  Map<String, dynamic>? payload,
  String currentStep = 'cadastre',
  String? scanUsdzKey,
  Map<String, dynamic>? scanFiles,
}) async {
  final session = await const AuthStorage().loadSession();
  final token = session.token;
  if (token == null || token.isEmpty) return null;
  final service = AiValuationJobService();
  try {
    final snap = await service.createDraft(
      payload: payload ?? const <String, dynamic>{},
      currentStep: currentStep,
      scanUsdzKey: scanUsdzKey,
      scanFiles: scanFiles,
      token: token,
    );
    return snap.id;
  } catch (_) {
    return null;
  } finally {
    service.dispose();
  }
}

/// Fire-and-forget draft save — UI'ni HECH QACHON bloklamaydi. Sekin yoki
/// ishlamayotgan backend wizard navigatsiyasini muzlatmasligi kerak, shuning
/// uchun chaqiruvchilar buni `await` qilishmaydi (xato/offline jim yutiladi).
void saveAiDraftStepInBackground(AiBaholashBundle bundle, String step) {
  unawaited(saveAiDraftStep(bundle, step));
}

/// DRAFT arizani joriy bundle bilan saqlaydi (qadam + payload). Jim ishlaydi —
/// xato/offline bo'lsa navigatsiyani to'xtatmaydi.
Future<void> saveAiDraftStep(AiBaholashBundle bundle, String nextStep) async {
  final id = bundle.draftId;
  if (id == null) return;
  final session = await const AuthStorage().loadSession();
  final token = session.token;
  if (token == null || token.isEmpty) return;
  final service = AiValuationJobService();
  try {
    await service.updateDraft(
      id,
      payload: bundle.toJson(),
      currentStep: nextStep,
      token: token,
    );
  } catch (_) {
    // jim — keyin retry
  } finally {
    service.dispose();
  }
}
