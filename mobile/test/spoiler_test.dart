import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/spoilers.dart';

void main() {
  test('spoiler policy hides only unrevealed completed races', () {
    expect(
      hidesRaceResult(
        enabled: true,
        phase: 'post_race',
        raceId: '2026-3',
        revealedSessions: {},
      ),
      isTrue,
    );
    expect(
      hidesRaceResult(
        enabled: true,
        phase: 'post_race',
        raceId: '2026-3',
        revealedSessions: {spoilerSessionKey('2026-3')},
      ),
      isFalse,
    );
    expect(
      hidesRaceResult(
        enabled: true,
        phase: 'race_weekend',
        raceId: '2026-3',
        revealedSessions: {},
      ),
      isFalse,
    );
  });
}
