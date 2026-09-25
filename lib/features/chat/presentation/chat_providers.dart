import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/chat_repository_impl.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';

final Provider<ChatRepository> chatRepositoryProvider =
    Provider<ChatRepository>((Ref ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ChatRepositoryImpl(apiClient: apiClient);
});

final StreamProviderFamily<List<ChatMessage>, String> conversationMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((Ref ref, String conversationId) {
  final ChatRepository repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(conversationId);
});
