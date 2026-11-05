
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/ble_discovery_service.dart';
import '../services/ble_gatt_service.dart';
import '../services/message_storage_service.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;
  final String contactId;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.contactId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];

  bool _isSending = false;
  bool _isLoading = true;
  bool _isNearBottom = true;

  String get _conversationId => widget.contactId.toLowerCase();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    MessageStorageService.updates.addListener(_onMessagesUpdated);

    _scrollController.addListener(_onScroll);

    _loadMessages(scrollToBottom: true);

    // Mark this conversation as active when the chat opens.
    _setActiveConversation();
  }

  // Tell Android that this conversation is currently open.
  Future<void> _setActiveConversation() async {
    try {
      await BleGattService.setActiveChat(_conversationId);

      debugPrint(
        'DisasterMesh: Active chat set to $_conversationId',
      );
    } catch (e) {
      debugPrint('DisasterMesh: Unable to set active chat: $e');
    }
  }

  // Tell Android that no conversation is currently active.
  Future<void> _clearActiveConversation() async {
    try {
      await BleGattService.clearActiveChat();

      debugPrint('DisasterMesh: Active chat cleared');
    } catch (e) {
      debugPrint('DisasterMesh: Unable to clear active chat: $e');
    }
  }

  // Detect when the app moves between foreground and background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // User returned to the app and this chat is visible again.
        _setActiveConversation();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // App is no longer actively visible.
        // Allow incoming messages to generate notifications.
        _clearActiveConversation();
        break;
    }
  }

  // Track whether the user is currently near the latest message.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _isNearBottom =
        position.maxScrollExtent - position.pixels <= 120;
  }

  void _onMessagesUpdated() {
    // Only auto-scroll if the user was already near the bottom.
    _loadMessages(scrollToBottom: _isNearBottom);
  }

  Future<void> _loadMessages({
    bool scrollToBottom = false,
  }) async {
    try {
      final savedMessages =
          await MessageStorageService.getConversationMessages(
        _conversationId,
      );

      if (!mounted) return;

      savedMessages.sort(
        (a, b) => (a['timestamp'] as int).compareTo(
          b['timestamp'] as int,
        ),
      );

      setState(() {
        _messages
          ..clear()
          ..addAll(savedMessages);

        _isLoading = false;
      });

      if (scrollToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;

          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        });
      }
    } catch (e) {
      debugPrint('Message loading error: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

    return TimeOfDay.fromDateTime(dateTime).format(context);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _isSending) return;

    if (!BleDiscoveryService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected to the nearby device.'),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await BleDiscoveryService.sendMessage(text);

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await MessageStorageService.saveMessage(
        conversationId: _conversationId,
        contactName: widget.contactName,
        senderId: 'me',
        senderName: 'You',
        text: text,
        timestamp: timestamp,
        isMe: true,
      );

      if (!mounted) return;

      _messageController.clear();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sending failed: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    MessageStorageService.updates.removeListener(_onMessagesUpdated);

    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    _messageController.dispose();

    // Clear active conversation when leaving this screen.
    _clearActiveConversation();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.contactName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              'Offline chat',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 42,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Start a conversation',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Messages are exchanged directly '
                                'between nearby devices.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message['isMe'] as bool;
                          final timestamp =
                              message['timestamp'] as int;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width *
                                        0.78,
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                12,
                                8,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.primary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft:
                                      Radius.circular(isMe ? 16 : 4),
                                  bottomRight:
                                      Radius.circular(isMe ? 4 : 16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    message['text'] as String,
                                    style: TextStyle(
                                      color: isMe
                                          ? AppColors.background
                                          : AppColors.textPrimary,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _formatTime(timestamp),
                                    style: TextStyle(
                                      color: isMe
                                          ? AppColors.background
                                              .withValues(alpha: 0.7)
                                          : AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
