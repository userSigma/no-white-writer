import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/text/composing.dart';
import '../state/workspace_controller.dart';

/// Navigation handshake: exposes the IME lock, never a copy of the draft.
class ChapterPaneDraft extends ValueNotifier<bool> {
  ChapterPaneDraft() : super(false);
  Future<bool> Function()? _submit;
  Future<bool> flush() => _submit?.call() ?? Future<bool>.value(true);
}

/// Owns one inline volume-name draft, including focus, IME and save lifetime.
class ChapterVolumeNameEditor extends ChangeNotifier {
  ChapterVolumeNameEditor({
    required this.workspace,
    required this.saveFailedLabel,
    ChapterPaneDraft? draft,
  }) {
    focus.addListener(_blur);
    name.addListener(_compositionChanged);
    bindDraft(draft);
  }

  final WorkspaceController workspace;
  final String Function() saveFailedLabel;
  final name = TextEditingController();
  final focus = FocusNode(debugLabel: 'volume-inline-name');
  ChapterPaneDraft? _draft;
  String? editingId, error;
  bool saving = false, _blurPending = false, _disposed = false;
  Future<bool>? _pending;
  bool get composing => isComposingValue(name.value);

  void bindDraft(ChapterPaneDraft? draft) {
    if (identical(draft, _draft)) return;
    if (_draft?._submit == submit) {
      _draft!._submit = null;
      _draft!.value = false;
    }
    _draft = draft;
    draft?._submit = submit;
    draft?.value = composing;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _blur() {
    if (!focus.hasFocus && editingId != null && !saving) {
      _blurPending = true;
      unawaited(submit());
    }
  }

  void _compositionChanged() {
    _draft?.value = composing;
    if (_blurPending && !composing && !saving && editingId != null) {
      scheduleMicrotask(submit);
    }
  }

  Future<bool> submit() {
    if (_disposed) return Future<bool>.value(false);
    if (_pending != null) return _pending!;
    late final Future<bool> request;
    request = _commit().whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
    _pending = request;
    return request;
  }

  Future<bool> _commit() async {
    if (editingId == null) return true;
    if (saving || composing) return false;
    _blurPending = false;
    final volume = workspace.book.volumes
        .where((v) => v.id == editingId)
        .firstOrNull;
    if (volume == null || name.text.trim() == volume.title) {
      editingId = null;
      _changed();
      return true;
    }
    saving = true;
    _changed();
    final ok = await workspace.renameVolume(volume, name.text.trim());
    if (_disposed) return ok;
    saving = false;
    if (ok) {
      editingId = null;
      error = null;
    } else {
      error = workspace.error ?? saveFailedLabel();
    }
    _changed();
    if (!ok) focus.requestFocus();
    return ok;
  }

  void cancel() {
    if (composing || saving) return;
    editingId = null;
    _blurPending = false;
    error = null;
    _changed();
    focus.unfocus();
  }

  Future<void> start(Volume volume) async {
    if (workspace.editingLocked ||
        workspace.moving ||
        workspace.editor.isComposing ||
        composing) {
      return;
    }
    if (editingId != null && !await submit()) return;
    if (_disposed) return;
    editingId = volume.id;
    error = null;
    name.value = TextEditingValue(
      text: volume.title,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: volume.title.length,
      ),
    );
    _changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    bindDraft(null);
    focus.removeListener(_blur);
    name.removeListener(_compositionChanged);
    name.dispose();
    focus.dispose();
    super.dispose();
  }
}

class ChapterVolumeNameField extends StatelessWidget {
  const ChapterVolumeNameField({
    super.key,
    required this.editor,
    required this.volumeId,
  });
  final ChapterVolumeNameEditor editor;
  final String volumeId;

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          !editor.composing) {
        editor.cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TextBox(
      key: ValueKey('volume-name-$volumeId'),
      controller: editor.name,
      focusNode: editor.focus,
      maxLines: 1,
      enabled: !editor.saving,
      onEditingComplete: () {},
      onSubmitted: (_) {
        if (!editor.composing) unawaited(editor.submit());
      },
    ),
  );
}
