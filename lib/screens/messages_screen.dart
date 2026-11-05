import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/message_storage_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _searchController = TextEditingController();

  int _selectedTab = 0;

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return TimeOfDay.fromDateTime(date).format(context);
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  List<Map<String, dynamic>> _getConversations(
    List<Map<String, dynamic>> messages,
  ) {
    final Map<String, Map<String, dynamic>> conversations = {};

    for (final message in messages) {
      final conversationId = message['conversationId'] as String?;

      if (conversationId == null || conversationId.isEmpty) {
        continue;
      }

      final existing = conversations[conversationId];

      if (existing == null ||
          (message['timestamp'] as int) > (existing['timestamp'] as int)) {
        conversations[conversationId] = message;
      }
    }

    final result = conversations.values.toList();

    result.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message requests will appear here.'),
                ),
              );
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Message requests',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Icon(Icons.tune, color: AppColors.textSecondary),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _MessageTab(
                  label: 'All',
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 10),
                _MessageTab(
                  label: 'Unread',
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
                const SizedBox(width: 10),
                _MessageTab(
                  label: 'Requests',
                  selected: _selectedTab == 2,
                  onTap: () {
                    setState(() => _selectedTab = 2);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message requests will appear here.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _selectedTab == 2
                ? _buildEmptyState(
                    'No message requests',
                    'Message requests will appear here.',
                  )
                : ValueListenableBuilder<int>(
                    valueListenable: MessageStorageService.updates,
                    builder: (context, version, child) {
                      return FutureBuilder<List<Map<String, dynamic>>>(
                        key: ValueKey(version),
                        future: MessageStorageService.getAllMessages(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return _buildEmptyState(
                              'Unable to load messages',
                              'Please try again later.',
                            );
                          }

                          final messages = snapshot.data ?? [];
                          var conversations = _getConversations(messages);

                          if (_selectedTab == 1) {
                            conversations = conversations.where((item) {
                              return item['isRead'] == false;
                            }).toList();
                          }

                          final search = _searchController.text
                              .trim()
                              .toLowerCase();

                          if (search.isNotEmpty) {
                            conversations = conversations.where((item) {
                              final name =
                                  (item['contactName'] as String? ?? '')
                                      .toLowerCase();
                              final text = (item['text'] as String? ?? '')
                                  .toLowerCase();

                              return name.contains(search) ||
                                  text.contains(search);
                            }).toList();
                          }

                          if (conversations.isEmpty) {
                            return _buildEmptyState(
                              _selectedTab == 1
                                  ? 'No unread messages'
                                  : 'No conversations yet',
                              _selectedTab == 1
                                  ? 'You are all caught up.'
                                  : 'Messages from nearby people will '
                                        'appear here. Start by discovering '
                                        'people around you.',
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: conversations.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final conversation = conversations[index];

                              final contactId =
                                  conversation['conversationId'] as String;

                              final contactName =
                                  conversation['contactName'] as String? ??
                                  'DisasterMesh User';

                              final lastMessage =
                                  conversation['text'] as String? ?? '';

                              final timestamp =
                                  conversation['timestamp'] as int;

                              final isMe =
                                  conversation['isMe'] as bool? ?? false;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                leading: CircleAvatar(
                                  radius: 25,
                                  backgroundColor: AppColors.surface,
                                  child: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.primary,
                                  ),
                                ),
                                title: Text(
                                  contactName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  '${isMe ? 'You: ' : ''}$lastMessage',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                trailing: Text(
                                  _formatTime(timestamp),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        contactName: contactName,
                                        contactId: contactId,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (_selectedTab == 0) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Open the Nearby tab to discover people.'),
                    ),
                  );
                },
                icon: const Icon(Icons.radar),
                label: const Text('Find Nearby People'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MessageTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.background : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
