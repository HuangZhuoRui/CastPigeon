part of '../cast_pigeon_home.dart';

class _ThemePreferenceSelector extends StatelessWidget {
  const _ThemePreferenceSelector({required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final selectedIndex = switch (themeController.themePreference) {
          AppThemePreference.light => 0,
          AppThemePreference.dark => 1,
          AppThemePreference.system => 2,
        };
        return Container(
          width: 104,
          height: 34,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _outlineColor(context)),
            boxShadow: [
              BoxShadow(
                color: _shadowColor(context).withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 230),
                curve: Curves.easeOutCubic,
                left: 3 + selectedIndex * 32,
                top: 3,
                width: 32,
                height: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              Row(
                children: [
                  _ThemePreferenceButton(
                    preference: AppThemePreference.light,
                    selected:
                        themeController.themePreference ==
                        AppThemePreference.light,
                    onTap: () => unawaited(
                      themeController.setThemePreference(
                        AppThemePreference.light,
                      ),
                    ),
                  ),
                  _ThemePreferenceButton(
                    preference: AppThemePreference.dark,
                    selected:
                        themeController.themePreference ==
                        AppThemePreference.dark,
                    onTap: () => unawaited(
                      themeController.setThemePreference(
                        AppThemePreference.dark,
                      ),
                    ),
                  ),
                  _ThemePreferenceButton(
                    preference: AppThemePreference.system,
                    selected:
                        themeController.themePreference ==
                        AppThemePreference.system,
                    onTap: () => unawaited(
                      themeController.setThemePreference(
                        AppThemePreference.system,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemePreferenceButton extends StatelessWidget {
  const _ThemePreferenceButton({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: selected ? 1.0 : 0.88,
              child: _ThemePreferenceGlyph(
                preference: preference,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreferenceGlyph extends StatelessWidget {
  const _ThemePreferenceGlyph({required this.preference, required this.color});

  final AppThemePreference preference;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (preference) {
      AppThemePreference.light => Icon(
        Icons.light_mode_rounded,
        size: 18,
        color: color,
      ),
      AppThemePreference.dark => Icon(
        Icons.dark_mode_rounded,
        size: 18,
        color: color,
      ),
      AppThemePreference.system => Text(
        'A',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    };
  }
}
