import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/language.dart';

import 'core/theme.dart';
import 'data/race_repository.dart';
import 'data/reminder_service.dart';
import 'features/home/home_page.dart';
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
  late final ReminderService? _reminders = widget.preferences == null
      ? null
      : ReminderService(widget.preferences!);
  late String _language = widget.preferences?.getString('language') == 'en'
      ? 'en'
      : 'zh';
  late bool _spoilerFree = widget.preferences?.getBool('spoilerFree') ?? false;
  late final Set<String> _revealedSessions =
      widget.preferences?.getStringList('spoilerRevealedSessions')?.toSet() ??
      <String>{};
  String t(String text) => translate(_language, text);
  Timer? _reminderTimer;
  bool _syncingReminders = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _syncReminders({bool requestPermissions = false}) async {
    if (_syncingReminders || _reminders?.supported != true) return;
    _syncingReminders = true;
    try {
      await _reminders!.syncUpcoming(
        _repository,
        _language,
        requestPermissions: requestPermissions,
      );
    } finally {
      _syncingReminders = false;
      if (mounted) setState(() {});
    }
  }

  void _changeLanguage(String language) {
    setState(() => _language = language);
    widget.preferences?.setString('language', language);
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
    WidgetsBinding.instance.removeObserver(this);
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'GrandPrixReminder',
    locale: Locale(_language),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: raceTheme(Brightness.light),
    darkTheme: raceTheme(Brightness.dark),
    home: Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: t('Settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(
                  spoilerFree: _spoilerFree,
                  onSpoilerFreeChanged: _changeSpoilerFree,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '语言 / Language',
            icon: const Icon(Icons.translate),
            initialValue: _language,
            onSelected: _changeLanguage,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'zh',
                checked: _language == 'zh',
                child: const Text('简体中文'),
              ),
              CheckedPopupMenuItem(
                value: 'en',
                checked: _language == 'en',
                child: const Text('English'),
              ),
            ],
          ),
        ],
        title: const Text(
          'GrandPrixReminder',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              key: ValueKey(_index),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: switch (_index) {
                0 => HomePage(
                  repository: _repository,
                  reminders: _reminders,
                  syncReminders: (request) =>
                      _syncReminders(requestPermissions: request),
                  spoilerFree: _spoilerFree,
                  revealedSessions: _revealedSessions,
                  onRevealSession: _revealSession,
                ),
                1 => RacesPage(
                  repository: _repository,
                  reminders: _reminders,
                  syncReminders: (request) =>
                      _syncReminders(requestPermissions: request),
                  spoilerFree: _spoilerFree,
                  revealedSessions: _revealedSessions,
                  onRevealSession: _revealSession,
                ),
                2 => const PlannedPage(
                  title: 'Briefing',
                  description: 'Driver insights, with the original sources.',
                  detail: 'Interview summaries will arrive after the race database is ready.',
                ),
                _ => const PlannedPage(
                  title: 'Evolution',
                  description: 'Follow what changes on the cars.',
                  detail: 'Verified upgrade timelines come first. Interactive car models follow.',
                ),
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.flag_outlined),
            label: t('Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            label: t('Races'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.article_outlined),
            label: t('Briefing'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.build_outlined),
            label: t('Evolution'),
          ),
        ],
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
