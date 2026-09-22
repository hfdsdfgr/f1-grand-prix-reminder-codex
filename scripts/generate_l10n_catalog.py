"""Mechanical ARB/catalog generation from the existing verified string pairs."""
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'mobile/lib/core/language.dart'
L10N = ROOT / 'mobile/lib/l10n'
CATALOG = ROOT / 'mobile/lib/l10n/localized_catalog.dart'


def main():
    source = SOURCE.read_text(encoding='utf-8')
    pairs = re.findall(r"'((?:\\.|[^'])*)'\s*:\s*'((?:\\.|[^'])*)'", source, re.S)
    translations = dict(pairs)
    if len(translations) < 100:
        raise RuntimeError('Expected the verified localization catalog')
    ids = {text: 's_' + hashlib.sha1(text.encode()).hexdigest()[:12] for text in translations}
    for locale, values in (('en', {key: key for key in translations}),
                           ('zh', translations), ('zh_CN', translations)):
        payload = {'@@locale': locale,
                   'appTitle': 'GrandPrixReminder',
                   'language': 'Language' if locale == 'en' else '语言',
                   'followSystem': 'Follow system' if locale == 'en' else '跟随系统',
                   'simplifiedChinese': 'Simplified Chinese' if locale == 'en' else '简体中文',
                   'english': 'English'}
        payload.update({ids[key]: value for key, value in values.items()})
        (L10N / f'app_{locale}.arb').write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    cases = '\n'.join(f"    {text!r} => strings.{field}," for text, field in ids.items())
    CATALOG.write_text("""// Generated from the verified ARB catalog. Do not edit by hand.
import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

String localizedText(BuildContext context, String text) {
  final strings = AppLocalizations.of(context);
  if (strings == null) return text;
  return switch (text) {
%s
    _ => text,
  };
}
""" % cases, encoding='utf-8')


if __name__ == '__main__':
    main()
