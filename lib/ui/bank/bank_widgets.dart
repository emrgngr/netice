import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../bank/bank_models.dart';
import '../../bank/bank_store.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import '../widgets.dart';

BankStore get bank => BankStore.instance;

Color difficultyColor(Difficulty d) => switch (d) {
      Difficulty.easy => NColors.emerald,
      Difficulty.medium => NColors.amber,
      Difficulty.hard => NColors.coral,
    };

IconData typeIcon(QuestionType t) => switch (t) {
      QuestionType.multiple => Icons.radio_button_checked_rounded,
      QuestionType.trueFalse => Icons.rule_rounded,
      QuestionType.fill => Icons.short_text_rounded,
      QuestionType.open => Icons.edit_note_rounded,
      QuestionType.matching => Icons.compare_arrows_rounded,
      QuestionType.trueFalseTable => Icons.fact_check_rounded,
      QuestionType.wordBank => Icons.space_bar_rounded,
      QuestionType.ordering => Icons.format_list_numbered_rounded,
    };

/// Küçük renkli etiket.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = NColors.emerald, this.icon});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (dark ? NColors.readable(color, dark: true) : color).withValues(alpha: dark ? 0.2 : 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: dark ? NColors.readable(color, dark: true) : _deep(color)), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dark ? NColors.readable(color, dark: true) : _deep(color))),
        ),
      ]),
    );
  }

  static Color _deep(Color c) => Color.lerp(c, Colors.black, 0.35)!;
}

class DifficultyPill extends StatelessWidget {
  final Difficulty d;
  const DifficultyPill(this.d, {super.key});

  @override
  Widget build(BuildContext context) => Pill(d.label, color: difficultyColor(d), icon: Icons.signal_cellular_alt_rounded);
}

/// Bankadaki bir görsel.
class BankImage extends StatelessWidget {
  final String? id;
  final double? height;
  final double? width;
  final BoxFit fit;
  const BankImage(this.id, {super.key, this.height, this.width, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final b = bank.imageBytes(id);
    if (b == null) {
      return SizedBox(
        height: height,
        width: width,
        child: Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.outline),
      );
    }
    return Image.memory(b, height: height, width: width, fit: fit, gaplessPlayback: true, filterQuality: FilterQuality.medium);
  }
}

/// Önerili metin kutusu (ders, konu, kazanım…).
class SuggestField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<String> Function() options;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  const SuggestField({super.key, required this.controller, required this.label, required this.options, this.icon, this.onChanged});

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: FocusNode(),
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          final all = options();
          if (q.isEmpty) return all.take(12);
          return all.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q).take(12);
        },
        fieldViewBuilder: (context, c, focus, submit) => TextField(
          controller: c,
          focusNode: focus,
          onChanged: onChanged,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
        ),
        optionsViewBuilder: (context, select, opts) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                children: [
                  for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => select(o)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Dosyayı telefonda paylaşır, bilgisayarda kaydettirir.
Future<void> shareOrSaveBytes(BuildContext context,
    {required Uint8List bytes, required String fileName, required String mime, String? message}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$fileName');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: mime)],
      text: message,
      subject: fileName,
      sharePositionOrigin: origin,
    ));
  } else {
    final path = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mime);
    if (path != null && context.mounted) toast(context, tr('Kaydedildi.'));
  }
}

String safeFileName(String s) {
  final t = s.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
  return t.isEmpty ? 'netice' : t;
}

/// Bölüm başlığı altında açıklamalı seçenek satırı (ekleme menüsü için).
class ActionTileData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const ActionTileData(this.icon, this.title, this.subtitle, this.onTap, {this.color = NColors.emerald});
}

Future<void> showActionSheet(BuildContext context, String title, List<ActionTileData> items) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final a in items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: IconBadge(a.icon, color: a.color),
                  title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(a.subtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
              ),
          ]),
        ),
      ),
    );

/// Boş durum: büyük simge, başlık, açıklama ve düğmeler.
class BankEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;
  const BankEmpty({super.key, required this.icon, required this.title, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [NColors.emerald.withValues(alpha: 0.18), NColors.emerald.withValues(alpha: 0.05)]),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Icon(icon, size: 42, color: NColors.emerald),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.4)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
        ],
      ]),
    );
  }
}

/// Çoklu seçimli süzgeç çipleri.
class ChoiceChips<T> extends StatelessWidget {
  final List<T> values;
  final Set<T> selected;
  final String Function(T) label;
  final ValueChanged<Set<T>> onChanged;
  final Color Function(T)? color;
  const ChoiceChips({super.key, required this.values, required this.selected, required this.label, required this.onChanged, this.color});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          FilterChip(
            label: Text(label(v)),
            selected: selected.contains(v),
            selectedColor: (color?.call(v) ?? NColors.emerald).withValues(alpha: 0.2),
            checkmarkColor: color?.call(v) ?? NColors.emerald,
            onSelected: (on) => onChanged(on ? ({...selected, v}) : ({...selected}..remove(v))),
          ),
      ]);
}
