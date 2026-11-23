import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The shared look of the demo: status colours, the formatting rules, and the small
/// widgets every screen builds from. Matches the Android and iOS apps.
class Ui {
  const Ui._();

  // Status colours, the same values as the Android `colors.xml`.
  static const Color statusMatch = Color(0xFF1B873F);
  static const Color statusNoMatch = Color(0xFFB26A00);
  static const Color statusInfo = Color(0xFF3D5AFE);
  static const Color danger = Color(0xFFC62828);
  static const Color accent = Color(0xFF3D5AFE);

  /// IDs are always shown as a pill tag "ID 12" — never "#12".
  static String idTag(int id) => 'ID $id';

  static String score(double v) => v.isFinite ? v.toStringAsFixed(2) : '–';

  static String angle(double v) => v.isFinite ? v.toStringAsFixed(1) : '–';

  /// Under 100 ms keeps one decimal; above it the decimal is noise.
  static String ms(double v) {
    if (!v.isFinite) return '–';
    return v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  static String facesCount(int n) => n == 1 ? '1 face' : '$n faces';

  static String matchesCount(int n) => n == 1 ? '1 match' : '$n matches';

  static String enrolledDate(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    return date == null ? iso : DateFormat.yMMMd().format(date);
  }

  static String enrolledDateTime(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    return date == null ? iso : DateFormat.yMMMd().add_jm().format(date);
  }

  static String time(DateTime? at) =>
      at == null ? '' : DateFormat.jms().format(at.toLocal());
}

/// A rounded, tinted label — the pill used for outcomes, IDs and badges.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color,
    this.fontSize = 12,
  });

  final String text;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final background = color ?? Theme.of(context).colorScheme.secondaryContainer;
    final onBackground =
        color == null ? Theme.of(context).colorScheme.onSecondaryContainer : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: onBackground,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The card every section and status block sits in.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// One big number with a caption under it. Used in rows of three.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Three metric tiles sharing the width equally.
class MetricsRow extends StatelessWidget {
  const MetricsRow({super.key, required this.tiles});

  final List<MetricTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// A titled card holding label/value rows — the Attribute and capture-check sections.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// How a [SectionRow] badge reads.
enum RowBadge { pass, fail, warn, info }

extension BadgeColor on RowBadge {
  Color get color => switch (this) {
        RowBadge.pass => Ui.statusMatch,
        RowBadge.fail => Ui.danger,
        RowBadge.warn => Ui.statusNoMatch,
        RowBadge.info => Ui.statusInfo,
      };
}

/// One label / value row, with an optional badge and a score bar under it.
class SectionRow extends StatefulWidget {
  const SectionRow({
    super.key,
    required this.label,
    required this.value,
    this.badge,
    this.score,
    this.collapsed = false,
    this.onTap,
  });

  final String label;
  final String value;
  final (String, RowBadge)? badge;

  /// 0..1 draws a bar under the row.
  final double? score;

  /// Long values (the landmark list) start clipped and expand on tap.
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  State<SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<SectionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = widget.badge;
    final score = widget.score;

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  widget.label,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Text(
                  widget.value,
                  maxLines: widget.collapsed && !_expanded ? 2 : null,
                  overflow: widget.collapsed && !_expanded
                      ? TextOverflow.ellipsis
                      : TextOverflow.clip,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Pill(badge.$1, color: badge.$2.color, fontSize: 11),
              ],
            ],
          ),
          if (score != null && score.isFinite) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: score.clamp(0, 1),
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                color: badge?.$2.color ?? Ui.accent,
              ),
            ),
          ],
        ],
      ),
    );

    final onTap = widget.onTap ??
        (widget.collapsed ? () => setState(() => _expanded = !_expanded) : null);
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

/// The one dialog the enroll flow uses for both of its steps — the capture review and the
/// enrollment status that follows. Full height, because both are lists the reader works
/// through rather than a one-line confirmation, and because two different surfaces for two
/// consecutive steps reads as two different screens.
///
/// The height is measured against what is actually free, so the keyboard shrinks the dialog
/// instead of pushing its buttons off a short screen.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> actions,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) {
      final height = appDialogHeight(context);
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: height,
          child: SingleChildScrollView(child: content),
        ),
        actions: actions,
      );
    },
  );
}

/// What the dialog body may use: the screen, less the keyboard, the dialog's own inset and
/// room for its title and buttons. Clamped so a very short screen still shows something.
double appDialogHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  const chrome = 24.0 * 2 + 150;
  final free = media.size.height - media.viewInsets.bottom - chrome;
  return free.clamp(180.0, double.infinity);
}

/// True while the keyboard is up, so a screen can give its images less room.
bool keyboardIsOpen(BuildContext context) =>
    MediaQuery.of(context).viewInsets.bottom > 0;
