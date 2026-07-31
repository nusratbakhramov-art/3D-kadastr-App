/// Yordamchi bot suhbatidagi bitta xabar.
enum ChatRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.isStreaming = false,
    this.isError = false,
    this.retryPrompt,
  });

  /// Xato qatori — assistant javobi emas, alohida ko'rinishda chiziladi.
  /// [retryPrompt] — qayta yuborilishi kerak bo'lgan foydalanuvchi savoli.
  factory ChatMessage.error(String content, {String? retryPrompt}) =>
      ChatMessage(
        role: ChatRole.assistant,
        content: content,
        isError: true,
        retryPrompt: retryPrompt,
      );

  final ChatRole role;

  /// Streaming paytida tokenlar qo'shilib boradi — shuning uchun o'zgaruvchan.
  String content;

  /// Assistant javobi hali oqayotgan bo'lsa true (typing indikatori uchun).
  bool isStreaming;

  /// True bo'lsa — bu bot javobi emas, xato holati. Bot belgisi bilan oddiy
  /// matn sifatida chizilsa, foydalanuvchi buni bot aytgan deb o'qiydi.
  final bool isError;

  /// Xato qatoridagi "Qayta urinish" tugmasi shu savolni qayta yuboradi.
  /// null bo'lsa — tugma ko'rsatilmaydi (qayta urinishga arzimaydigan xato).
  final String? retryPrompt;

  bool get isUser => role == ChatRole.user;
}
