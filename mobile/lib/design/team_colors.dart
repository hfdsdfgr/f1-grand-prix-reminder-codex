import 'package:flutter/material.dart';

/// Shared editorial accents. RGB sources and visibility adjustments are
/// documented in docs/team-identity.md; no logo assets are used.
class TeamVisualIdentity {
  final String key, abbreviation, displayName;
  final Color color;
  final List<String> aliases;
  const TeamVisualIdentity(
    this.key,
    this.abbreviation,
    this.displayName,
    this.color,
    this.aliases,
  );
}

// API IDs verified against the public 2026 roster. Canonical keys also match
// the existing client car catalogue; ID aliases take priority over names.
const teamVisualIdentities = <TeamVisualIdentity>[
  TeamVisualIdentity('alpine', 'ALP', 'Alpine F1 Team', Color(0xFF2173B8), [
    'tea_6cb810a7efa544a6b5e66e18b91ea0c7',
    'alpine',
    'alpine f1 team',
  ]),
  TeamVisualIdentity('aston_martin', 'AST', 'Aston Martin', Color(0xFF357C73), [
    'tea_a505f37998334e82ae7550c9b004ddb9',
    'aston_martin',
    'aston martin',
  ]),
  TeamVisualIdentity('audi', 'AUD', 'Audi', Color(0xFFCE494E), [
    'tea_b116b1a50b90457f809a57bbcff4836e',
    'audi',
  ]),
  TeamVisualIdentity('cadillac', 'CAD', 'Cadillac F1 Team', Color(0xFFBFC3C7), [
    'tea_eb442a2372704fdeaa5c210af3eef2b0',
    'cadillac',
    'cadillac f1 team',
  ]),
  TeamVisualIdentity('ferrari', 'FER', 'Ferrari', Color(0xFFEF1A2D), [
    'tea_b491d6ac02754baea2892bfcd6330f4c',
    'ferrari',
  ]),
  TeamVisualIdentity('haas', 'HAA', 'Haas F1 Team', Color(0xFFE6002B), [
    'tea_e0cc9a00b812476faa69462517559dc9',
    'haas',
    'haas f1 team',
  ]),
  TeamVisualIdentity('mclaren', 'MCL', 'McLaren', Color(0xFFFF8000), [
    'tea_b6c207b7090e4951bf52df083d466525',
    'mclaren',
  ]),
  TeamVisualIdentity('mercedes', 'MER', 'Mercedes', Color(0xFF00A19B), [
    'tea_73852d577a3e4d60be8a9128438ea18c',
    'mercedes',
  ]),
  TeamVisualIdentity('racing_bulls', 'RB', 'RB F1 Team', Color(0xFF798FD0), [
    'tea_8ee70d3e0bdb429c915c713342fa2bbf',
    'rb',
    'rb f1 team',
    'racing bulls',
  ]),
  TeamVisualIdentity('redbull', 'RBR', 'Red Bull', Color(0xFFFDD900), [
    'tea_5844e7c6941b4e289cfa482f02209dc7',
    'red_bull',
    'red bull',
    'redbull',
  ]),
  TeamVisualIdentity('williams', 'WIL', 'Williams', Color(0xFF00A0DE), [
    'tea_2b8ac937c02141b6979096304be6b431',
    'williams',
  ]),
];

const unknownTeamIdentity = TeamVisualIdentity(
  'unknown',
  'UNK',
  'Unknown',
  Color(0xFF92999F),
  [],
);

TeamVisualIdentity teamVisualIdentity({String? teamId, String? teamName}) {
  final id = teamId?.trim().toLowerCase();
  for (final team in teamVisualIdentities) {
    if (id == team.key || team.aliases.contains(id)) return team;
  }
  final name = teamName?.trim().toLowerCase();
  for (final team in teamVisualIdentities) {
    if (name == team.displayName.toLowerCase() || team.aliases.contains(name)) {
      return team;
    }
  }
  return unknownTeamIdentity;
}
