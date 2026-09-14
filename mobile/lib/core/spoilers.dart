String spoilerSessionKey(String raceId, [String session = 'Race']) =>
    '$raceId:$session';

bool hidesRaceResult({
  required bool enabled,
  required String phase,
  required String raceId,
  required Set<String> revealedSessions,
}) =>
    enabled &&
    phase == 'post_race' &&
    !revealedSessions.contains(spoilerSessionKey(raceId));
