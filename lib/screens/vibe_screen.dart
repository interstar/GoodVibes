import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xybrid_flutter/xybrid_flutter.dart';

import '../services/app_catalog.dart';
import '../services/app_generator.dart';
import '../services/llm_service.dart';
import '../services/local_server.dart';
import '../services/settings_service.dart';
import 'app_window.dart';

/// A single chat entry in the Studio.
class _ChatMessage {
  final bool fromUser;
  final String text;
  String? errorDetail;
  InstalledApp? installedApp;
  bool get isApp => installedApp != null;

  _ChatMessage({required this.fromUser, required this.text});
}

/// The Vibe Studio: chat with the LLM to generate new apps, or edit an
/// existing app in place.
class VibeScreen extends StatefulWidget {
  final AppCatalog catalog;
  final LlmService llm;
  final SettingsService settings;
  final LocalServer server;

  /// When set, the Studio edits this app: its files are sent along and the
  /// result replaces the app in place.
  final InstalledApp? editTarget;
  final ValueChanged<InstalledApp?>? onEditTargetChanged;

  const VibeScreen({
    super.key,
    required this.catalog,
    required this.llm,
    required this.settings,
    required this.server,
    this.editTarget,
    this.onEditTargetChanged,
  });

  @override
  State<VibeScreen> createState() => _VibeScreenState();
}

class _VibeScreenState extends State<VibeScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  ConversationContext? _context;
  String? _referenceAppId;
  String? _pendingUserMessage;
  bool _streaming = false;
  String _streamingText = '';
  CancellationToken? _cancel;
  String? _status;
  InstalledApp? _editTarget;

  @override
  void initState() {
    super.initState();
    _editTarget = widget.editTarget;
  }

  @override
  void didUpdateWidget(VibeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.editTarget?.manifest.id;
    final newId = widget.editTarget?.manifest.id;
    if (oldId != newId) {
      if (widget.editTarget != null) {
        // A new app was picked for editing: drop any reference app / prior
        // conversation context.
        _referenceAppId = null;
        _context = null;
      }
      // Keep the local copy fresh (e.g. after a catalog refresh).
      setState(() => _editTarget = widget.editTarget);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetConversation() async {
    _cancel?.cancel();
    setState(() {
      _messages.clear();
      _context = null;
      _streaming = false;
      _streamingText = '';
      _status = null;
    });
  }

  Future<void> _send({bool retry = false}) async {
    if (_streaming) return;
    final text = retry ? (_pendingUserMessage ?? '') : _inputController.text.trim();
    if (text.isEmpty) return;

    if (!retry) {
      _inputController.clear();
      _pendingUserMessage = text;
      setState(() => _messages.add(_ChatMessage(fromUser: true, text: text)));
    }
    await _generate(text);
  }

  Future<void> _generate(String userText) async {
    setState(() {
      _streaming = true;
      _streamingText = '';
      _status = null;
    });

    final context = _context ??= ConversationContext();

    try {
      final system = await AppGenerator.buildSystemPrompt(
        installedApps: widget.catalog.apps,
        referenceApp: _editTarget == null
            ? (_referenceAppId == null
                ? null
                : widget.catalog.byId(_referenceAppId!))
            : null,
        editApp: _editTarget,
      );
      if (!context.hasSystem) {
        context.setSystem(system);
      }

      // First use without an API key downloads the on-device weights; surface
      // that progress instead of a silent wait.
      setState(() => _status = 'Loading the model…');
      await widget.llm.ensureModel(onEvent: (event) {
        if (event is LoadProgress && mounted) {
          setState(() => _status = 'Downloading model… ${event.percentage}%');
        } else if (event is LoadError && mounted) {
          setState(() => _status = 'Model download failed: ${event.message}');
        }
      });

      final cancel = _cancel = CancellationToken();
      final buffer = StringBuffer();
      var failed = false;

      await for (final token in widget.llm.streamChat(
        context,
        userText,
        cancellationToken: cancel,
      )) {
        if (!mounted) return;
        if (token.isError) {
          failed = true;
          setState(() {
            _status = 'Error: ${token.errorMessage ?? 'unknown error'}';
            _streamingText = buffer.toString();
          });
          break;
        }
        buffer.write(token.token);
        if (mounted) {
          setState(() => _streamingText = buffer.toString());
        }
        _scrollToBottom();
      }

      if (!mounted) return;
      final fullText = buffer.toString().trim();
      context.pushText(fullText, MessageRole.assistant);

      if (failed || fullText.isEmpty) {
        setState(() {
          _streaming = false;
          _messages.add(_ChatMessage(fromUser: false, text: fullText.isEmpty
              ? '(no response)'
              : fullText)
            ..errorDetail = _status ?? 'The model did not respond.');
        });
        return;
      }

      _ChatMessage? parsed;
      try {
        final generated = AppGenerator.parse(fullText);
        final appsDir = await widget.settings.appsDir();
        final target = _editTarget;
        final installed = await AppGenerator.write(
          appsDir: appsDir,
          app: generated,
          overrideId: target?.manifest.id,
          keepUnmentionedFiles: target != null,
        );
        await widget.catalog.refresh();
        parsed = _ChatMessage(fromUser: false, text: fullText)
          ..installedApp = installed;
        final missing = AppGenerator.findMissingReferences(
          generated,
          existingDir: target == null ? null : Directory(target.dir),
        );
        setState(() {
          _status = target == null
              ? 'Created "${generated.name}" — tap Open to run it right away.'
              : 'Updated "${target.manifest.name}" — tap Open to see the changes.';
          if (missing.isNotEmpty) {
            _status = '${_status!}\nWarning: ${missing.map((f) => '"$f"').join(', ')} '
                'is referenced but was not generated.';
          }
        });
      } on GenerateParseException catch (e) {
        setState(() {
          _status = e.message;
        });
        parsed = _ChatMessage(fromUser: false, text: fullText)
          ..errorDetail = e.message;
      } catch (e) {
        setState(() {
          _status = 'Could not install the app: $e';
        });
        parsed = _ChatMessage(fromUser: false, text: fullText)
          ..errorDetail = 'Could not install the app: $e';
      }

      if (mounted) {
        setState(() {
          _messages.add(parsed!);
          _streaming = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _streaming = false;
          _status = 'Generation failed: $e';
          _messages.add(_ChatMessage(fromUser: false, text: '')
            ..errorDetail = 'Generation failed: $e');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _streaming = false);
      }
    }
  }

  void _stop() {
    _cancel?.cancel();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _showStructureInfo() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How apps work'),
        content: SingleChildScrollView(
          child: Text(
            AppGenerator.appStructureSpec,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vibe Studio'),
        actions: [
          IconButton(
            tooltip: 'How apps work',
            icon: const Icon(Icons.info_outline),
            onPressed: _showStructureInfo,
          ),
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _streaming ? null : _resetConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_editTarget != null) _editBanner(context) else _referenceBar(context),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty && _streamingText.isEmpty
                ? _emptyState(context)
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in _messages) ...[
                        if (m.fromUser)
                          _UserBubble(text: m.text)
                        else
                          _AssistantBubble(
                            text: m.text,
                            errorDetail: m.errorDetail,
                            installedApp: m.installedApp,
                            server: widget.server,
                            onRetry: m.errorDetail == null
                                ? null
                                : () => _send(retry: true),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (_streaming)
                        _AssistantBubble(
                          text: _streamingText,
                          streaming: true,
                        ),
                    ],
                  ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          _inputBar(context),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Build an app with a sentence.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Try: "a pomodoro timer that chimes when a session ends" or\n'
              '"a habit tracker with a weekly grid".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editBanner(BuildContext context) {
    final theme = Theme.of(context);
    final target = _editTarget!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.edit_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'Editing "${target.manifest.name}"',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                    text: ' — describe a change; it will replace the app.'),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Stop editing',
            icon: const Icon(Icons.close),
            onPressed: _streaming
                ? null
                : () => widget.onEditTargetChanged?.call(null),
          ),
        ],
      ),
    );
  }

  Widget _referenceBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(Icons.style_outlined,
              size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          const Text('Match the style of:'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: ListenableBuilder(
                listenable: widget.catalog,
                builder: (context, _) {
                  final apps = widget.catalog.apps;
                  return DropdownButton<String?>(
                    isExpanded: true,
                    value: _referenceAppId,
                    hint: const Text('No reference app'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No reference app'),
                      ),
                      for (final app in apps)
                        DropdownMenuItem<String?>(
                          value: app.manifest.id,
                          child: Text(
                            app.manifest.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _streaming
                        ? null
                        : (value) {
                            if (value == _referenceAppId) return;
                            setState(() {
                              _referenceAppId = value;
                              // A different exemplar means a different context.
                              _context = null;
                            });
                          },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: !_streaming,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _editTarget == null
                      ? 'Describe an app to build…'
                      : 'Describe what to add or change…',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            if (_streaming)
              IconButton.filledTonal(
                tooltip: 'Stop',
                icon: const Icon(Icons.stop),
                onPressed: _stop,
              )
            else
              FilledButton(
                onPressed: _send,
                child: const Icon(Icons.send),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: SelectableText(text),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  final String? errorDetail;
  final InstalledApp? installedApp;
  final LocalServer? server;
  final VoidCallback? onRetry;
  final bool streaming;

  const _AssistantBubble({
    required this.text,
    this.errorDetail,
    this.installedApp,
    this.server,
    this.onRetry,
    this.streaming = false,
  });

  Future<void> _openApp(BuildContext context) async {
    if (installedApp == null || server == null) return;
    try {
      await openAppInBrowser(
        url: server!.urlForApp(installedApp!.manifest.id),
        title: installedApp!.manifest.name,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the app: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = installedApp;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty) SelectableText(text),
            if (streaming)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      text.isEmpty ? 'Thinking…' : 'Generating…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (errorDetail != null) ...[
              const SizedBox(height: 8),
              Text(
                errorDetail!,
                style: TextStyle(color: scheme.error),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ],
            if (app != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _openApp(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text('Open ${app.manifest.name}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
