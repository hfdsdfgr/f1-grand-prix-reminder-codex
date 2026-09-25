import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/language.dart';
import 'l10n/app_localizations.dart';

import 'core/theme.dart';
import 'data/follow_service.dart';
import 'data/race_repository.dart';
import 'data/reminder_service.dart';
import 'features/home/home_page.dart';
import 'features/briefing/briefing_page.dart';
import 'features/evolution/evolution_page.dart';
import 'features/races/races_page.dart';
import 'features/settings/settings_page.dart';

class GrandPrixApp extends StatefulWidget {
  final RaceRepository? repository;
  final SharedPreferences? preferences;
  const GrandPrixApp({super.key, this.repository, this.preferences});
  @override
  State<GrandPrixApp> createState() => _GrandPrixAppState();
}

class _GrandPrixAppState extends State<GrandPrixApp>
    with WidgetsBindingObserver {
  late final RaceRepository _repository =
      widget.repository ?? RaceRepository(preferences: widget.preferences);
  int _index = 0;
  bool _briefingOpen = false;
  String? _briefingRaceId;
  late final ReminderService? _reminders = widget.preferences == null
      ? null
      : ReminderService(widget.preferences!);
  late final FollowService? _follows = widget.preferences == null
      ? null
      : FollowService(widget.preferences!);
  late String? _language = switch (widget.preferences?.getString('language')) {
    'en' => 'en',
    'zh-CN' || 'zh' => 'zh-CN',
    _ => null,
  };
  late bool _spoilerFree = widget.preferences?.getBool('spoilerFree') ?? false;
  late final Set<String> _revealedSessions =
      widget.preferences?.getStringList('spoilerRevealedSessions')?.toSet() ??
      <String>{};
  String get _effectiveLanguage =>
      _language ??
      (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh'
          ? 'zh-CN'
          : 'en');
  String t(String text) => translate(_effectiveLanguage, text);
  Timer? _reminderTimer;
  bool _syncingReminders = false;

  @override
  void initState() {
    super.initState();
    _repository.language = _effectiveLanguage;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncReminders();
    });
    _reminderTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _syncReminders(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncReminders();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_language != null) return;
    _repository.language = _effectiveLanguage;
    setState(() {});
    _syncReminders();
  }

  Future<void> _syncReminders({bool requestPermissions = false}) async {
    if (_syncingReminders || _reminders?.supported != true) return;
    _syncingReminders = true;
    try {
      await _reminders!.syncUpcoming(
        _repository,
        _effectiveLanguage,
        requestPermissions: requestPermissions,
      );
    } finally {
      _syncingReminders = false;
      if (mounted) setState(() {});
    }
  }

  void _changeLanguage(String? language) {
    setState(() => _language = language);
    _repository.language = _effectiveLanguage;
    if (language == null) {
      widget.preferences?.remove('language');
    } else {
      widget.preferences?.setString('language', language);
    }
    _syncReminders();
  }

  void _changeSpoilerFree(bool enabled) {
    setState(() => _spoilerFree = enabled);
    widget.preferences?.setBool('spoilerFree', enabled);
  }

  void _revealSession(String key) {
    setState(() => _revealedSessions.add(key));
    widget.preferences?.setStringList(
      'spoilerRevealedSessions',
      _revealedSessions.toList(),
    );
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _follows?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'GrandPrixReminder',
    locale: switch (_language) {
      'zh-CN' => const Locale('zh', 'CN'),
      'en' => const Locale('en'),
      _ => null,
    },
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: raceTheme(Brightness.light),
    darkTheme: raceTheme(Brightness.dark),
    themeMode: ThemeMode.dark,
    home: PopScope(
      canPop: !_briefingOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _briefingOpen) setState(() => _briefingOpen = false);
      },
      child: Scaffold(
        appBar: _index == 3 || (_index == 0 && !_briefingOpen)
            ? null
            : AppBar(
                toolbarHeight: 44,
                leading: _briefingOpen
                    ? BackButton(
                        onPressed: () => setState(() => _briefingOpen = false),
                      )
                    : null,
              ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: RaceSpace.contentWidth,
              ),
              child: _index == 3
                  ? SettingsPage(
                      spoilerFree: _spoilerFree,
                      onSpoilerFreeChanged: _changeSpoilerFree,
                      follows: _follows,
                      language: _language,
                      onLanguageChanged: _changeLanguage,
                    )
                  : SingleChildScrollView(
                      key: PageStorageKey(
                        _briefingOpen
                            ? 'briefing-$_briefingRaceId'
                            : 'page-$_index',
                      ),
                      padding: RaceSpace.page,
                      child: _briefingOpen && _index == 0
                          ? BriefingPage(
                              repository: _repository,
                              initialRaceId: _briefingRaceId,
                              spoilerFree: _spoilerFree,
                              revealedSessions: _revealedSessions,
                              onRevealSession: _revealSession,
                              follows: _follows,
                            )
                          : switch (_index) {
                              0 => HomePage(
                                onOpenBriefing: (raceId) => setState(() {
                                  _briefingRaceId = raceId;
                                  _briefingOpen = true;
                                }),
                                repository: _repository,
                                reminders: _reminders,
                                syncReminders: (request) =>
                                    _syncReminders(requestPermissions: request),
                                spoilerFree: _spoilerFree,
                                revealedSessions: _revealedSessions,
                                onRevealSession: _revealSession,
                                follows: _follows,
                              ),
                              1 => RacesPage(
                                repository: _repository,
                                reminders: _reminders,
                                syncReminders: (request) =>
                                    _syncReminders(requestPermissions: request),
                                spoilerFree: _spoilerFree,
                                revealedSessions: _revealedSessions,
                                onRevealSession: _revealSession,
                                follows: _follows,
                              ),
                              _ => EvolutionPage(
                                repository: _repository,
                                follows: _follows,
                              ),
                            },
                    ),
            ),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFF3B4143), width: .5),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() {
              _index = index;
              _briefingOpen = false;
            }),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: t('Home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.calendar_month_outlined),
                label: t('Calendar'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: t('Explore'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                label: t('Settings'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlannedPage extends StatelessWidget {
  final String title, description, detail;
  const PlannedPage({
    super.key,
    required this.title,
    required this.description,
    required this.detail,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr(context, title), style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 24),
      Text(
        tr(context, description),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 24),
      Text(tr(context, 'Coming later')),
      const SizedBox(height: 8),
      Text(
        tr(context, detail),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}
