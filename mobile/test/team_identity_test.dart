import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/design/team_colors.dart';
import 'package:grand_prix_reminder/shared/team_identity.dart';
import 'package:grand_prix_reminder/l10n/app_localizations.dart';

void main() {
  test('all 11 real API team IDs resolve, even if display names change', () {
    final feed = jsonDecode(
      File('test/fixtures/evolution/2026-en.json').readAsStringSync(),
    ) as Map;
    final cars = feed['cars'] as List;
    final keys = <String>{};
    for (final car in cars) {
      final identity = teamVisualIdentity(
        teamId: car['team_id'] as String,
        teamName: 'Renamed team',
      );
      expect(identity, isNot(unknownTeamIdentity));
      keys.add(identity.key);
    }
    expect(keys, hasLength(11));
    expect(
      teamVisualIdentity(teamId: 'mclaren', teamName: 'Ferrari').abbreviation,
      'MCL',
    );
    expect(teamVisualIdentity(teamName: ' McLaren ').key, 'mclaren');
    expect(
      teamVisualIdentity(teamId: 'future-team', teamName: 'New Team'),
      unknownTeamIdentity,
    );
    expect(teamVisualIdentity(), unknownTeamIdentity);
  });

  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    for (final size in TeamIdentitySize.values) {
      testWidgets(
        '${locale.toLanguageTag()} $size uses text and fits narrow enlarged layouts',
        (t) async {
          final semantics = t.ensureSemantics();

          await t.pumpWidget(
            MaterialApp(
              theme: raceTheme(Brightness.dark),
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TeamIdentity(
                            teamId: 'mclaren',
                            teamName: 'McLaren',
                            size: size,
                          ),
                          TeamIdentity(
                            teamId: 'future-team',
                            teamName:
                                'A new team with a very long display name',
                            size: size,
                          ),
                          TeamIdentity(size: size),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.bySemanticsLabel('MCL, McLaren'), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              'UNK, A new team with a very long display name',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              size == TeamIdentitySize.compact
                  ? 'MCL'
                  : size == TeamIdentitySize.standard
                  ? 'MCL  McLaren'
                  : 'McLaren',
            ),
            findsOneWidget,
          );
          final marker = t
              .widgetList<ColoredBox>(
                find.descendant(
                  of: find.byType(TeamIdentity).first,
                  matching: find.byType(ColoredBox),
                ),
              )
              .single;
          expect(marker.color, const Color(0xFFFF8000));
          expect(
            find.descendant(
              of: find.byType(TeamIdentity),
              matching: find.byType(InkWell),
            ),
            findsNothing,
          );
          semantics.dispose();
        },
      );
    }
  }
}
