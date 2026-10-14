import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notes_db.dart';
import '../logic/export_text.dart';
import '../logic/native.dart';
import '../theme.dart';
import 'widgets.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.days});

  final Set<int> days;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String? _text;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    NotesDb.notesForDays(widget.days).then((notes) {
      if (mounted) setState(() => _text = buildExportText(notes));
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  // The app only ever writes to the clipboard, and only on this tap.
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _text!));
    } catch (_) {
      // Android's clipboard can't hold very large text; Share sends it as a file instead.
      if (mounted) showSnack(ScaffoldMessenger.of(context), 'Too long to copy. Use Share to send it as a file.');
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // A file is what Import reads on another phone; Share sends short exports as plain text.
  Future<void> _save(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = 'jnote-${DateTime.now().toIso8601String().substring(0, 10)}.txt';
      if (await Native.saveText(name, text)) showSnack(messenger, 'Saved as a text file.');
    } on PlatformException {
      showSnack(messenger, "Couldn't save the file. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final text = _text;
    final n = widget.days.length;
    // Laying out years of notes at once would freeze the screen, so a long preview stops at a day break.
    final cut = text == null || text.length <= 40000 ? -1 : text.indexOf('\n\n', 40000);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Export'),
            Text(
              '$n ${n == 1 ? 'day' : 'days'} · plain text',
              style: tt.bodySmall!.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (text != null && text.isNotEmpty)
            IconButton(icon: const Icon(Icons.save_alt), tooltip: 'Save as file', onPressed: () => _save(text)),
        ],
      ),
      body: text == null
          ? const SizedBox.shrink()
          : text.isEmpty
          ? Center(
              child: Text('No notes on the selected days.', style: tt.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
            )
          : readable(
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                      ),
                      child: SelectableText(
                        cut < 0 ? text : text.substring(0, cut),
                        style: plainText.copyWith(color: cs.onSurface),
                      ),
                    ),
                    if (cut >= 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                        child: Text(
                          'The preview stops here. Copy and Share include all $n days.',
                          style: tt.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: text == null || text.isEmpty
          ? null
          : SafeArea(
              child: readable(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Native.share(text).catchError((Object _) {
                            if (context.mounted) {
                              showSnack(ScaffoldMessenger.of(context), "Couldn't open sharing. Please try again.");
                            }
                          }),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _copy,
                          icon: Icon(_copied ? Icons.check : Icons.content_copy, size: 18),
                          label: Text(_copied ? 'Copied' : 'Copy'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
