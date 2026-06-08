/// Yordamchi bot suhbatidagi bitta xabar.
enum ChatRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  final ChatRole role;

  /// Streaming paytida tokenlar qo'shilib boradi — shuning uchun o'zgaruvchan.
  String content;

  /// Assistant javobi hali oqayotgan bo'lsa true (typing indikatori uchun).
  bool isStreaming;

  bool get isUser => role == ChatRole.user;
}
