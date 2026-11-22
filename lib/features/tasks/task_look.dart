import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../managers/task_views.dart';

/// Desktop's type icons are Lucide names; these are the nearest Material ones.
IconData typeIcon(String name) => switch (name) {
  'bug' => Icons.bug_report_outlined,
  'sparkles' => Icons.auto_awesome_outlined,
  'trending-up' => Icons.trending_up,
  'wrench' => Icons.build_outlined,
  'square-check' => Icons.check_box_outlined,
  'book-open' => Icons.menu_book_outlined,
  'file-text' => Icons.description_outlined,
  'circle-question-mark' => Icons.help_outline,
  'flask-conical' => Icons.science_outlined,
  'rocket' => Icons.rocket_launch_outlined,
  'shield' => Icons.shield_outlined,
  'palette' => Icons.palette_outlined,
  'zap' => Icons.bolt_outlined,
  _ => Icons.radio_button_checked,
};

/// The colours of desktop's tones, readable on light and dark backgrounds.
Color toneColor(String? tone, ColorScheme scheme) => switch (tone) {
  'red' => const Color(0xFFE5484D),
  'orange' => const Color(0xFFF76B15),
  'yellow' => const Color(0xFFD9A800),
  'green' => const Color(0xFF30A46C),
  'blue' => const Color(0xFF3E8BEF),
  'purple' => const Color(0xFF8E4EC6),
  'gray' => scheme.outline,
  _ => scheme.onSurfaceVariant,
};

Color statusColor(StatusTone tone, ColorScheme scheme) => switch (tone) {
  StatusTone.gray => scheme.outline,
  StatusTone.blue => toneColor('blue', scheme),
  StatusTone.yellow => toneColor('yellow', scheme),
  StatusTone.purple => toneColor('purple', scheme),
  StatusTone.orange => toneColor('orange', scheme),
  StatusTone.green => toneColor('green', scheme),
  StatusTone.other => scheme.onSurfaceVariant,
};

Color labelColor(String label) =>
    HSLColor.fromAHSL(1, labelHue(label).toDouble(), 0.65, 0.6).toColor();

class TypeIcon extends StatelessWidget {
  const TypeIcon({
    super.key,
    required this.type,
    required this.types,
    this.size = 14,
  });
  final String type;
  final List<TaskType> types;
  final double size;

  @override
  Widget build(BuildContext context) {
    final look = typeLook(type, types);
    return Tooltip(
      message: titleCase(type),
      child: Icon(
        typeIcon(look.icon),
        size: size,
        color: toneColor(look.tone, Theme.of(context).colorScheme),
      ),
    );
  }
}

class PriorityIcon extends StatelessWidget {
  const PriorityIcon({super.key, required this.priority, this.size = 15});
  final String priority;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (priority) {
      'urgent' => (Icons.priority_high, toneColor('red', scheme)),
      'high' => (Icons.keyboard_double_arrow_up, toneColor('orange', scheme)),
      'medium' => (Icons.drag_handle, toneColor('yellow', scheme)),
      'low' => (Icons.keyboard_arrow_down, scheme.outline),
      _ => (Icons.remove, scheme.outline),
    };
    return Tooltip(
      message: titleCase(priority),
      child: Icon(icon, size: size, color: color),
    );
  }
}

/// A person's initials in a circle tinted by their name.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.isEmpty
        ? '?'
        : words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: HSLColor.fromAHSL(
          1,
          labelHue(name).toDouble(),
          0.45,
          0.45,
        ).toColor(),
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.42,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class LabelChip extends StatelessWidget {
  const LabelChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = labelColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
