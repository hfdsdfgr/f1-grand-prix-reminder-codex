import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'GrandPrixReminder'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @s_89b86ab0e66f.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get s_89b86ab0e66f;

  /// No description provided for @s_1b16bcb011f7.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get s_1b16bcb011f7;

  /// No description provided for @s_e03f20a90b59.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get s_e03f20a90b59;

  /// No description provided for @s_c6150bb60e44.
  ///
  /// In en, this message translates to:
  /// **'Generic model'**
  String get s_c6150bb60e44;

  /// No description provided for @s_76f93e8a0bd6.
  ///
  /// In en, this message translates to:
  /// **'Generic illustration'**
  String get s_76f93e8a0bd6;

  /// No description provided for @s_4878a0d94690.
  ///
  /// In en, this message translates to:
  /// **'Car archive'**
  String get s_4878a0d94690;

  /// No description provided for @s_d127855aea08.
  ///
  /// In en, this message translates to:
  /// **'Team-inspired colours only; not an official livery.'**
  String get s_d127855aea08;

  /// No description provided for @s_364e486e4b83.
  ///
  /// In en, this message translates to:
  /// **'Identity verified; generation geometry unavailable. Showing the generic illustration.'**
  String get s_364e486e4b83;

  /// No description provided for @s_d2bce6052869.
  ///
  /// In en, this message translates to:
  /// **'Official Car'**
  String get s_d2bce6052869;

  /// No description provided for @s_faef9afd6bc2.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the official page.'**
  String get s_faef9afd6bc2;

  /// No description provided for @s_85e7e1a2ba3b.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the car model.'**
  String get s_85e7e1a2ba3b;

  /// No description provided for @s_b71e9a51346f.
  ///
  /// In en, this message translates to:
  /// **'Loading car model'**
  String get s_b71e9a51346f;

  /// No description provided for @s_8704d0ad6894.
  ///
  /// In en, this message translates to:
  /// **'Front view'**
  String get s_8704d0ad6894;

  /// No description provided for @s_2ef560c18144.
  ///
  /// In en, this message translates to:
  /// **'Side view'**
  String get s_2ef560c18144;

  /// No description provided for @s_9d597493304a.
  ///
  /// In en, this message translates to:
  /// **'Top view'**
  String get s_9d597493304a;

  /// No description provided for @s_3638caec792a.
  ///
  /// In en, this message translates to:
  /// **'Rear view'**
  String get s_3638caec792a;

  /// No description provided for @s_89511a76c8cb.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get s_89511a76c8cb;

  /// No description provided for @s_06b2c135c0cd.
  ///
  /// In en, this message translates to:
  /// **'What does it do?'**
  String get s_06b2c135c0cd;

  /// No description provided for @s_de807e418751.
  ///
  /// In en, this message translates to:
  /// **'Why does it matter?'**
  String get s_de807e418751;

  /// No description provided for @s_90bf34a130ed.
  ///
  /// In en, this message translates to:
  /// **'Static draft awaiting human review. Current specification and upgrades: unavailable.'**
  String get s_90bf34a130ed;

  /// No description provided for @s_3f83cef14f65.
  ///
  /// In en, this message translates to:
  /// **'Component labels'**
  String get s_3f83cef14f65;

  /// No description provided for @s_a5be156d0e86.
  ///
  /// In en, this message translates to:
  /// **'Wireframe'**
  String get s_a5be156d0e86;

  /// No description provided for @s_6c4aecc855d9.
  ///
  /// In en, this message translates to:
  /// **'Focus component'**
  String get s_6c4aecc855d9;

  /// No description provided for @s_7e5a730b0201.
  ///
  /// In en, this message translates to:
  /// **'Deconstruct'**
  String get s_7e5a730b0201;

  /// No description provided for @s_fb22c3c1f968.
  ///
  /// In en, this message translates to:
  /// **'Assemble'**
  String get s_fb22c3c1f968;

  /// No description provided for @s_df9fff105479.
  ///
  /// In en, this message translates to:
  /// **'Livery'**
  String get s_df9fff105479;

  /// No description provided for @s_41fc0860886a.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get s_41fc0860886a;

  /// No description provided for @s_8d105cf44d39.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get s_8d105cf44d39;

  /// No description provided for @s_50f94286ba30.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get s_50f94286ba30;

  /// No description provided for @s_4fc0e2bc8073.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get s_4fc0e2bc8073;

  /// No description provided for @s_166989cc6333.
  ///
  /// In en, this message translates to:
  /// **'Ghost Compare'**
  String get s_166989cc6333;

  /// No description provided for @s_0e0447a5124f.
  ///
  /// In en, this message translates to:
  /// **'Overlay the previous geometry over the current car.'**
  String get s_0e0447a5124f;

  /// No description provided for @s_c0edf949676b.
  ///
  /// In en, this message translates to:
  /// **'Two verified generation geometries are required.'**
  String get s_c0edf949676b;

  /// No description provided for @s_fad9c2603cf6.
  ///
  /// In en, this message translates to:
  /// **'Overlay the previous race specification over the current car.'**
  String get s_fad9c2603cf6;

  /// No description provided for @s_1ff8edb12dec.
  ///
  /// In en, this message translates to:
  /// **'Two sourced race specifications are required.'**
  String get s_1ff8edb12dec;

  /// No description provided for @s_becccecd09bf.
  ///
  /// In en, this message translates to:
  /// **'No sourced component differences are available.'**
  String get s_becccecd09bf;

  /// No description provided for @s_70734c104e83.
  ///
  /// In en, this message translates to:
  /// **'Heritage'**
  String get s_70734c104e83;

  /// No description provided for @s_5f75233b080d.
  ///
  /// In en, this message translates to:
  /// **'Generation Compare'**
  String get s_5f75233b080d;

  /// No description provided for @s_dece7f1f4699.
  ///
  /// In en, this message translates to:
  /// **'Specification Compare'**
  String get s_dece7f1f4699;

  /// No description provided for @s_227787bb0b8d.
  ///
  /// In en, this message translates to:
  /// **'Launch specification'**
  String get s_227787bb0b8d;

  /// No description provided for @s_2f8887b68c48.
  ///
  /// In en, this message translates to:
  /// **'Explore the car'**
  String get s_2f8887b68c48;

  /// No description provided for @s_d12ed1b8c0e7.
  ///
  /// In en, this message translates to:
  /// **'Generic model — not a team specification.'**
  String get s_d12ed1b8c0e7;

  /// No description provided for @s_2d80f948aa26.
  ///
  /// In en, this message translates to:
  /// **'Interactive car model'**
  String get s_2d80f948aa26;

  /// No description provided for @s_09e11a379667.
  ///
  /// In en, this message translates to:
  /// **'Drag to rotate · Pinch to zoom'**
  String get s_09e11a379667;

  /// No description provided for @s_87a90fe1bf1b.
  ///
  /// In en, this message translates to:
  /// **'Car component'**
  String get s_87a90fe1bf1b;

  /// No description provided for @s_eb9f9930aed6.
  ///
  /// In en, this message translates to:
  /// **'Nose'**
  String get s_eb9f9930aed6;

  /// No description provided for @s_458c4eb70672.
  ///
  /// In en, this message translates to:
  /// **'Engine Cover'**
  String get s_458c4eb70672;

  /// No description provided for @s_e9b1c042eac9.
  ///
  /// In en, this message translates to:
  /// **'Beam Wing'**
  String get s_e9b1c042eac9;

  /// No description provided for @s_6f72f3cd1255.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get s_6f72f3cd1255;

  /// No description provided for @s_b75f23d1d0e4.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get s_b75f23d1d0e4;

  /// No description provided for @s_4fc05f2763ba.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get s_4fc05f2763ba;

  /// No description provided for @s_a4ae4b24a1f5.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get s_a4ae4b24a1f5;

  /// No description provided for @s_80d8db7ad9bc.
  ///
  /// In en, this message translates to:
  /// **'Reset view'**
  String get s_80d8db7ad9bc;

  /// No description provided for @s_d9e17f44e4bc.
  ///
  /// In en, this message translates to:
  /// **'Front Suspension'**
  String get s_d9e17f44e4bc;

  /// No description provided for @s_f02915871479.
  ///
  /// In en, this message translates to:
  /// **'Front Tyres'**
  String get s_f02915871479;

  /// No description provided for @s_2a00508ee7e5.
  ///
  /// In en, this message translates to:
  /// **'Rear Suspension'**
  String get s_2a00508ee7e5;

  /// No description provided for @s_806f5ed8f1ba.
  ///
  /// In en, this message translates to:
  /// **'Rear Tyres'**
  String get s_806f5ed8f1ba;

  /// No description provided for @s_ae0283c88bd1.
  ///
  /// In en, this message translates to:
  /// **'Previous season'**
  String get s_ae0283c88bd1;

  /// No description provided for @s_c0263a85c4bf.
  ///
  /// In en, this message translates to:
  /// **'Next season'**
  String get s_c0263a85c4bf;

  /// No description provided for @s_77c69345abb0.
  ///
  /// In en, this message translates to:
  /// **'Loading upgrades'**
  String get s_77c69345abb0;

  /// No description provided for @s_fe40055ba98f.
  ///
  /// In en, this message translates to:
  /// **'Unable to load upgrades. Please retry.'**
  String get s_fe40055ba98f;

  /// No description provided for @s_608d1568de13.
  ///
  /// In en, this message translates to:
  /// **'Showing saved upgrades. They may have changed.'**
  String get s_608d1568de13;

  /// No description provided for @s_b57abdbfcd68.
  ///
  /// In en, this message translates to:
  /// **'No sourced upgrades are available for this season.'**
  String get s_b57abdbfcd68;

  /// No description provided for @s_218887269ad5.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get s_218887269ad5;

  /// No description provided for @s_e75f540d4c14.
  ///
  /// In en, this message translates to:
  /// **'All teams'**
  String get s_e75f540d4c14;

  /// No description provided for @s_e8e3a1800af9.
  ///
  /// In en, this message translates to:
  /// **'Grand Prix'**
  String get s_e8e3a1800af9;

  /// No description provided for @s_f2d08edd9f58.
  ///
  /// In en, this message translates to:
  /// **'All races'**
  String get s_f2d08edd9f58;

  /// No description provided for @s_ee09eebdb55b.
  ///
  /// In en, this message translates to:
  /// **'Upgrade timeline'**
  String get s_ee09eebdb55b;

  /// No description provided for @s_4227c0148e31.
  ///
  /// In en, this message translates to:
  /// **'Season Evolution'**
  String get s_4227c0148e31;

  /// No description provided for @s_a6f47e00e036.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get s_a6f47e00e036;

  /// No description provided for @s_86f3dfedf8be.
  ///
  /// In en, this message translates to:
  /// **'No recorded upgrade'**
  String get s_86f3dfedf8be;

  /// No description provided for @s_636e1af4af77.
  ///
  /// In en, this message translates to:
  /// **'This upgrade has no compatible 3D component mapping.'**
  String get s_636e1af4af77;

  /// No description provided for @s_64fbd995d3b6.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get s_64fbd995d3b6;

  /// No description provided for @s_9fe00acebc10.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get s_9fe00acebc10;

  /// No description provided for @s_f819748c7128.
  ///
  /// In en, this message translates to:
  /// **'Expected effect'**
  String get s_f819748c7128;

  /// No description provided for @s_8259026556ce.
  ///
  /// In en, this message translates to:
  /// **'introduced'**
  String get s_8259026556ce;

  /// No description provided for @s_880949479ab1.
  ///
  /// In en, this message translates to:
  /// **'tested'**
  String get s_880949479ab1;

  /// No description provided for @s_bc175d397c7e.
  ///
  /// In en, this message translates to:
  /// **'retained'**
  String get s_bc175d397c7e;

  /// No description provided for @s_99db32474282.
  ///
  /// In en, this message translates to:
  /// **'modified'**
  String get s_99db32474282;

  /// No description provided for @s_69992f174744.
  ///
  /// In en, this message translates to:
  /// **'removed'**
  String get s_69992f174744;

  /// No description provided for @s_50d8b4a941c2.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get s_50d8b4a941c2;

  /// No description provided for @s_7331419266ad.
  ///
  /// In en, this message translates to:
  /// **'Front Wing'**
  String get s_7331419266ad;

  /// No description provided for @s_7db82f74092f.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get s_7db82f74092f;

  /// No description provided for @s_3edd19033ac5.
  ///
  /// In en, this message translates to:
  /// **'Rear Wing'**
  String get s_3edd19033ac5;

  /// No description provided for @s_fe06fdf5f02e.
  ///
  /// In en, this message translates to:
  /// **'Sidepods'**
  String get s_fe06fdf5f02e;

  /// No description provided for @s_9ec17b948fc1.
  ///
  /// In en, this message translates to:
  /// **'Automatically remind me of upcoming races'**
  String get s_9ec17b948fc1;

  /// No description provided for @s_5105665ec868.
  ///
  /// In en, this message translates to:
  /// **'One hour before every published race, including the next race.'**
  String get s_5105665ec868;

  /// No description provided for @s_7c0f0086060e.
  ///
  /// In en, this message translates to:
  /// **'Session settings below override this race only.'**
  String get s_7c0f0086060e;

  /// No description provided for @s_a715bcd29d7e.
  ///
  /// In en, this message translates to:
  /// **'Automatic race reminders: 1 hour before each race.'**
  String get s_a715bcd29d7e;

  /// No description provided for @s_2fa61cd4fb20.
  ///
  /// In en, this message translates to:
  /// **'Automatic race reminders are off.'**
  String get s_2fa61cd4fb20;

  /// No description provided for @s_883b6f4699ad.
  ///
  /// In en, this message translates to:
  /// **'Scheduled races'**
  String get s_883b6f4699ad;

  /// No description provided for @s_bc7df07bafc7.
  ///
  /// In en, this message translates to:
  /// **'Check permissions and sync reminders'**
  String get s_bc7df07bafc7;

  /// No description provided for @s_a9e8e0da3bae.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh reminders. Existing reminders are kept.'**
  String get s_a9e8e0da3bae;

  /// No description provided for @s_022b53a4cb41.
  ///
  /// In en, this message translates to:
  /// **'Some schedules could not be refreshed. Existing reminders are kept.'**
  String get s_022b53a4cb41;

  /// No description provided for @s_e00dce877daa.
  ///
  /// In en, this message translates to:
  /// **'Race reminders'**
  String get s_e00dce877daa;

  /// No description provided for @s_28cbf8443b86.
  ///
  /// In en, this message translates to:
  /// **'Reminders apply to this race only.'**
  String get s_28cbf8443b86;

  /// No description provided for @s_af7b2f1b05b9.
  ///
  /// In en, this message translates to:
  /// **'Local reminders are available in the Android and iOS apps.'**
  String get s_af7b2f1b05b9;

  /// No description provided for @s_55de44432c09.
  ///
  /// In en, this message translates to:
  /// **'Refresh the schedule before creating a reminder.'**
  String get s_55de44432c09;

  /// No description provided for @s_f7f1997c6cd1.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get s_f7f1997c6cd1;

  /// No description provided for @s_25df3f712aa2.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get s_25df3f712aa2;

  /// No description provided for @s_d904716454a7.
  ///
  /// In en, this message translates to:
  /// **'24 hours before'**
  String get s_d904716454a7;

  /// No description provided for @s_f2a1e2cbf054.
  ///
  /// In en, this message translates to:
  /// **'1 hour before'**
  String get s_f2a1e2cbf054;

  /// No description provided for @s_4bba5a72574f.
  ///
  /// In en, this message translates to:
  /// **'15 minutes before'**
  String get s_4bba5a72574f;

  /// No description provided for @s_081ae3fdc403.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get s_081ae3fdc403;

  /// No description provided for @s_99ff37be3fb6.
  ///
  /// In en, this message translates to:
  /// **'Minutes before start'**
  String get s_99ff37be3fb6;

  /// No description provided for @s_1b90e575eaad.
  ///
  /// In en, this message translates to:
  /// **'minutes before start'**
  String get s_1b90e575eaad;

  /// No description provided for @s_4ce3e05e66a7.
  ///
  /// In en, this message translates to:
  /// **'Starts in'**
  String get s_4ce3e05e66a7;

  /// No description provided for @s_be2e2bb698c7.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get s_be2e2bb698c7;

  /// No description provided for @s_f961953acc62.
  ///
  /// In en, this message translates to:
  /// **'Saved reminder'**
  String get s_f961953acc62;

  /// No description provided for @s_fd3167aadb7d.
  ///
  /// In en, this message translates to:
  /// **'Schedule changed. Save again to update your reminder.'**
  String get s_fd3167aadb7d;

  /// No description provided for @s_aabeb4ac40d9.
  ///
  /// In en, this message translates to:
  /// **'Choose 1 to 10080 minutes.'**
  String get s_aabeb4ac40d9;

  /// No description provided for @s_03ae53b0b068.
  ///
  /// In en, this message translates to:
  /// **'This reminder time has already passed.'**
  String get s_03ae53b0b068;

  /// No description provided for @s_6751c7c0b3cb.
  ///
  /// In en, this message translates to:
  /// **'Unable to initialize notifications.'**
  String get s_6751c7c0b3cb;

  /// No description provided for @s_e2ad7357275f.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications in system settings, then retry.'**
  String get s_e2ad7357275f;

  /// No description provided for @s_999b93e0950f.
  ///
  /// In en, this message translates to:
  /// **'Allow alarms and reminders in system settings, then retry.'**
  String get s_999b93e0950f;

  /// No description provided for @s_93081ac58a7e.
  ///
  /// In en, this message translates to:
  /// **'Unable to save reminder. Please retry.'**
  String get s_93081ac58a7e;

  /// No description provided for @s_322e31405ae7.
  ///
  /// In en, this message translates to:
  /// **'Reminder scheduled.'**
  String get s_322e31405ae7;

  /// No description provided for @s_970e356bad13.
  ///
  /// In en, this message translates to:
  /// **'Reminder cancelled.'**
  String get s_970e356bad13;

  /// No description provided for @s_12e9efc0e183.
  ///
  /// In en, this message translates to:
  /// **'Save reminder'**
  String get s_12e9efc0e183;

  /// No description provided for @s_f9bb73574cf5.
  ///
  /// In en, this message translates to:
  /// **'Cancel reminder'**
  String get s_f9bb73574cf5;

  /// No description provided for @s_56a2285c5b11.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get s_56a2285c5b11;

  /// No description provided for @s_bbfa773e5a63.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get s_bbfa773e5a63;

  /// No description provided for @s_e1ef34564d16.
  ///
  /// In en, this message translates to:
  /// **'Race details'**
  String get s_e1ef34564d16;

  /// No description provided for @s_7d270b60a39a.
  ///
  /// In en, this message translates to:
  /// **'Race result'**
  String get s_7d270b60a39a;

  /// No description provided for @s_aadfe94f3443.
  ///
  /// In en, this message translates to:
  /// **'Race story'**
  String get s_aadfe94f3443;

  /// No description provided for @s_aeb01b1235d7.
  ///
  /// In en, this message translates to:
  /// **'Strategy view'**
  String get s_aeb01b1235d7;

  /// No description provided for @s_36ee21494ba3.
  ///
  /// In en, this message translates to:
  /// **'Tyre compounds and verified pit laps.'**
  String get s_36ee21494ba3;

  /// No description provided for @s_3e58550ec999.
  ///
  /// In en, this message translates to:
  /// **'Loading strategy'**
  String get s_3e58550ec999;

  /// No description provided for @s_5be53df0baab.
  ///
  /// In en, this message translates to:
  /// **'Unable to load strategy. Please try again.'**
  String get s_5be53df0baab;

  /// No description provided for @s_261c5b354ed0.
  ///
  /// In en, this message translates to:
  /// **'Showing saved strategy. It may have changed.'**
  String get s_261c5b354ed0;

  /// No description provided for @s_b242bd2e3b05.
  ///
  /// In en, this message translates to:
  /// **'Strategy data is not available yet.'**
  String get s_b242bd2e3b05;

  /// No description provided for @s_61d337149d57.
  ///
  /// In en, this message translates to:
  /// **'Source: FastF1'**
  String get s_61d337149d57;

  /// No description provided for @s_b32fa4b27ada.
  ///
  /// In en, this message translates to:
  /// **'Championship impact'**
  String get s_b32fa4b27ada;

  /// No description provided for @s_3ac14ea05946.
  ///
  /// In en, this message translates to:
  /// **'Standings after this race, compared with the previous round.'**
  String get s_3ac14ea05946;

  /// No description provided for @s_c683d3ae9ca9.
  ///
  /// In en, this message translates to:
  /// **'Loading championship impact'**
  String get s_c683d3ae9ca9;

  /// No description provided for @s_fee5d6cf0873.
  ///
  /// In en, this message translates to:
  /// **'Unable to load championship impact. Please try again.'**
  String get s_fee5d6cf0873;

  /// No description provided for @s_fa697efb5c83.
  ///
  /// In en, this message translates to:
  /// **'Showing saved championship impact. It may have changed.'**
  String get s_fa697efb5c83;

  /// No description provided for @s_b548fd71bafa.
  ///
  /// In en, this message translates to:
  /// **'Championship data is not available yet.'**
  String get s_b548fd71bafa;

  /// No description provided for @s_35208af6069c.
  ///
  /// In en, this message translates to:
  /// **'Drivers’ championship'**
  String get s_35208af6069c;

  /// No description provided for @s_594def24da84.
  ///
  /// In en, this message translates to:
  /// **'Constructors’ championship'**
  String get s_594def24da84;

  /// No description provided for @s_819f41f05837.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get s_819f41f05837;

  /// No description provided for @s_0e648419ea80.
  ///
  /// In en, this message translates to:
  /// **'Stops'**
  String get s_0e648419ea80;

  /// No description provided for @s_310f4fb80f85.
  ///
  /// In en, this message translates to:
  /// **'Pit'**
  String get s_310f4fb80f85;

  /// No description provided for @s_bbf1f8fee0d6.
  ///
  /// In en, this message translates to:
  /// **'Tyre age'**
  String get s_bbf1f8fee0d6;

  /// No description provided for @s_968c009e49bf.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get s_968c009e49bf;

  /// No description provided for @s_d404968ea90b.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get s_d404968ea90b;

  /// No description provided for @s_20a89915f18c.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get s_20a89915f18c;

  /// No description provided for @s_b1cfe72fd271.
  ///
  /// In en, this message translates to:
  /// **'Intermediate'**
  String get s_b1cfe72fd271;

  /// No description provided for @s_9429cfe23a19.
  ///
  /// In en, this message translates to:
  /// **'Wet'**
  String get s_9429cfe23a19;

  /// No description provided for @s_1b480158e1f3.
  ///
  /// In en, this message translates to:
  /// **'stop'**
  String get s_1b480158e1f3;

  /// No description provided for @s_2a4524950358.
  ///
  /// In en, this message translates to:
  /// **'stops'**
  String get s_2a4524950358;

  /// No description provided for @s_f62b5cf8180a.
  ///
  /// In en, this message translates to:
  /// **'Key race facts'**
  String get s_f62b5cf8180a;

  /// No description provided for @s_01c5122cf527.
  ///
  /// In en, this message translates to:
  /// **'Loading race story'**
  String get s_01c5122cf527;

  /// No description provided for @s_56cbc718b7f0.
  ///
  /// In en, this message translates to:
  /// **'Unable to load race story. Please try again.'**
  String get s_56cbc718b7f0;

  /// No description provided for @s_bdc2d7c088cc.
  ///
  /// In en, this message translates to:
  /// **'Showing saved race story. It may have changed.'**
  String get s_bdc2d7c088cc;

  /// No description provided for @s_515adccc4805.
  ///
  /// In en, this message translates to:
  /// **'Race story is not available yet.'**
  String get s_515adccc4805;

  /// No description provided for @s_b11a37dc600f.
  ///
  /// In en, this message translates to:
  /// **'Biggest gain'**
  String get s_b11a37dc600f;

  /// No description provided for @s_f6b0d3ae2f25.
  ///
  /// In en, this message translates to:
  /// **'Biggest loss'**
  String get s_f6b0d3ae2f25;

  /// No description provided for @s_952f375412e8.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get s_952f375412e8;

  /// No description provided for @s_b74bdee9c34f.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get s_b74bdee9c34f;

  /// No description provided for @s_d766a0ac4523.
  ///
  /// In en, this message translates to:
  /// **'View results'**
  String get s_d766a0ac4523;

  /// No description provided for @s_badd385121c5.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get s_badd385121c5;

  /// No description provided for @s_4e3adcfe37c3.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get s_4e3adcfe37c3;

  /// No description provided for @s_d4b8ec0c9b97.
  ///
  /// In en, this message translates to:
  /// **'Loading results'**
  String get s_d4b8ec0c9b97;

  /// No description provided for @s_b5166581397b.
  ///
  /// In en, this message translates to:
  /// **'Unable to load results. Please try again.'**
  String get s_b5166581397b;

  /// No description provided for @s_dbf92862c56f.
  ///
  /// In en, this message translates to:
  /// **'Showing saved results. They may have changed.'**
  String get s_dbf92862c56f;

  /// No description provided for @s_c636b8c21f9c.
  ///
  /// In en, this message translates to:
  /// **'Results have not been published or are unavailable for this session.'**
  String get s_c636b8c21f9c;

  /// No description provided for @s_187557ec15f5.
  ///
  /// In en, this message translates to:
  /// **'Fastest lap'**
  String get s_187557ec15f5;

  /// No description provided for @s_e3abd1b61219.
  ///
  /// In en, this message translates to:
  /// **'Lap'**
  String get s_e3abd1b61219;

  /// No description provided for @s_d1a17af19f53.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get s_d1a17af19f53;

  /// No description provided for @s_5619a03401d5.
  ///
  /// In en, this message translates to:
  /// **'Unknown team'**
  String get s_5619a03401d5;

  /// No description provided for @s_d27ff0598f08.
  ///
  /// In en, this message translates to:
  /// **'Time / Gap'**
  String get s_d27ff0598f08;

  /// No description provided for @s_701c483f813c.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get s_701c483f813c;

  /// No description provided for @s_4b2a6a314956.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get s_4b2a6a314956;

  /// No description provided for @s_bae7d5be7082.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get s_bae7d5be7082;

  /// No description provided for @s_230881dbae69.
  ///
  /// In en, this message translates to:
  /// **'Pit lane / unlisted'**
  String get s_230881dbae69;

  /// No description provided for @s_355bcc577d71.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get s_355bcc577d71;

  /// No description provided for @s_a525f885e521.
  ///
  /// In en, this message translates to:
  /// **'Disqualified'**
  String get s_a525f885e521;

  /// No description provided for @s_37d1213e53ce.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get s_37d1213e53ce;

  /// No description provided for @s_ce926764b220.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get s_ce926764b220;

  /// No description provided for @s_92b493e1f561.
  ///
  /// In en, this message translates to:
  /// **'Collision'**
  String get s_92b493e1f561;

  /// No description provided for @s_c1f65ddb75ed.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get s_c1f65ddb75ed;

  /// No description provided for @s_b1ba8f0c934d.
  ///
  /// In en, this message translates to:
  /// **'Gearbox'**
  String get s_b1ba8f0c934d;

  /// No description provided for @s_605541fa322e.
  ///
  /// In en, this message translates to:
  /// **'Did not start'**
  String get s_605541fa322e;

  /// No description provided for @s_70f8bb9a8a53.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get s_70f8bb9a8a53;

  /// No description provided for @s_9af3f864702b.
  ///
  /// In en, this message translates to:
  /// **'Races'**
  String get s_9af3f864702b;

  /// No description provided for @s_084694536bd1.
  ///
  /// In en, this message translates to:
  /// **'Briefing'**
  String get s_084694536bd1;

  /// No description provided for @s_a0eead72abab.
  ///
  /// In en, this message translates to:
  /// **'Verified driver and team insights, with original sources.'**
  String get s_a0eead72abab;

  /// No description provided for @s_e5ead1a3459e.
  ///
  /// In en, this message translates to:
  /// **'Loading race briefing'**
  String get s_e5ead1a3459e;

  /// No description provided for @s_33794931cf87.
  ///
  /// In en, this message translates to:
  /// **'Unable to load race briefing. Please try again.'**
  String get s_33794931cf87;

  /// No description provided for @s_d7dc3bfcac02.
  ///
  /// In en, this message translates to:
  /// **'Showing saved briefing. It may have changed.'**
  String get s_d7dc3bfcac02;

  /// No description provided for @s_21dcdf59d075.
  ///
  /// In en, this message translates to:
  /// **'No verified briefing is available for this race.'**
  String get s_21dcdf59d075;

  /// No description provided for @s_239de103e613.
  ///
  /// In en, this message translates to:
  /// **'No completed race is available for briefing.'**
  String get s_239de103e613;

  /// No description provided for @s_2eb56be3c2d9.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get s_2eb56be3c2d9;

  /// No description provided for @s_0cccd48e35ce.
  ///
  /// In en, this message translates to:
  /// **'Technical themes'**
  String get s_0cccd48e35ce;

  /// No description provided for @s_30a5c875e032.
  ///
  /// In en, this message translates to:
  /// **'Team performance'**
  String get s_30a5c875e032;

  /// No description provided for @s_1a1406a86d10.
  ///
  /// In en, this message translates to:
  /// **'Tyre issues'**
  String get s_1a1406a86d10;

  /// No description provided for @s_4b64edbbdf88.
  ///
  /// In en, this message translates to:
  /// **'Strategy issues'**
  String get s_4b64edbbdf88;

  /// No description provided for @s_2a44959ab9b0.
  ///
  /// In en, this message translates to:
  /// **'Upgrade feedback'**
  String get s_2a44959ab9b0;

  /// No description provided for @s_bee1f1e9d451.
  ///
  /// In en, this message translates to:
  /// **'Driver concerns'**
  String get s_bee1f1e9d451;

  /// No description provided for @s_8566d18186dc.
  ///
  /// In en, this message translates to:
  /// **'Next-race expectations'**
  String get s_8566d18186dc;

  /// No description provided for @s_f760e16023bf.
  ///
  /// In en, this message translates to:
  /// **'Evolution'**
  String get s_f760e16023bf;

  /// No description provided for @s_62255f5671e8.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get s_62255f5671e8;

  /// No description provided for @s_b955ddcd0d58.
  ///
  /// In en, this message translates to:
  /// **'Next Grand Prix'**
  String get s_b955ddcd0d58;

  /// No description provided for @s_c268226e5629.
  ///
  /// In en, this message translates to:
  /// **'Your local time'**
  String get s_c268226e5629;

  /// No description provided for @s_f573f24f963c.
  ///
  /// In en, this message translates to:
  /// **'Start time to be confirmed'**
  String get s_f573f24f963c;

  /// No description provided for @s_d909f1f13f50.
  ///
  /// In en, this message translates to:
  /// **'Time to be confirmed'**
  String get s_d909f1f13f50;

  /// No description provided for @s_33b77e7b3df5.
  ///
  /// In en, this message translates to:
  /// **'Race weekend'**
  String get s_33b77e7b3df5;

  /// No description provided for @s_28f71da3aa9c.
  ///
  /// In en, this message translates to:
  /// **'Pre-race'**
  String get s_28f71da3aa9c;

  /// No description provided for @s_dd92daf07e79.
  ///
  /// In en, this message translates to:
  /// **'Post-race'**
  String get s_dd92daf07e79;

  /// No description provided for @s_e8ae2dcb43aa.
  ///
  /// In en, this message translates to:
  /// **'Current session'**
  String get s_e8ae2dcb43aa;

  /// No description provided for @s_ff7122bba14f.
  ///
  /// In en, this message translates to:
  /// **'Next session'**
  String get s_ff7122bba14f;

  /// No description provided for @s_0d877d2ce15c.
  ///
  /// In en, this message translates to:
  /// **'Next session starts in'**
  String get s_0d877d2ce15c;

  /// No description provided for @s_68b42a762071.
  ///
  /// In en, this message translates to:
  /// **'Weekend schedule'**
  String get s_68b42a762071;

  /// No description provided for @s_96fb83160557.
  ///
  /// In en, this message translates to:
  /// **'Weekend hub'**
  String get s_96fb83160557;

  /// No description provided for @s_523baab918ef.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get s_523baab918ef;

  /// No description provided for @s_65c821a596ce.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get s_65c821a596ce;

  /// No description provided for @s_1798b3ba42ee.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get s_1798b3ba42ee;

  /// No description provided for @s_cc6e7b6a2974.
  ///
  /// In en, this message translates to:
  /// **'Delayed'**
  String get s_cc6e7b6a2974;

  /// No description provided for @s_a1bf92eff40d.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get s_a1bf92eff40d;

  /// No description provided for @s_b6859aa3120d.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled'**
  String get s_b6859aa3120d;

  /// No description provided for @s_e991a769148e.
  ///
  /// In en, this message translates to:
  /// **'Status unknown'**
  String get s_e991a769148e;

  /// No description provided for @s_6b4cbaaddeec.
  ///
  /// In en, this message translates to:
  /// **'circuit layout'**
  String get s_6b4cbaaddeec;

  /// No description provided for @s_7cb1b2d771fb.
  ///
  /// In en, this message translates to:
  /// **'turns'**
  String get s_7cb1b2d771fb;

  /// No description provided for @s_c7f73bb54d92.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get s_c7f73bb54d92;

  /// No description provided for @s_90eeb1008380.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get s_90eeb1008380;

  /// No description provided for @s_699cb0068a73.
  ///
  /// In en, this message translates to:
  /// **'Following this season'**
  String get s_699cb0068a73;

  /// No description provided for @s_520b22642d87.
  ///
  /// In en, this message translates to:
  /// **'Showing saved follow context. It may have changed.'**
  String get s_520b22642d87;

  /// No description provided for @s_306cbbc97e31.
  ///
  /// In en, this message translates to:
  /// **'Follow driver'**
  String get s_306cbbc97e31;

  /// No description provided for @s_453b172697f7.
  ///
  /// In en, this message translates to:
  /// **'Following driver'**
  String get s_453b172697f7;

  /// No description provided for @s_dd7d6f5b49ce.
  ///
  /// In en, this message translates to:
  /// **'Follow team'**
  String get s_dd7d6f5b49ce;

  /// No description provided for @s_9f8a384d1fa2.
  ///
  /// In en, this message translates to:
  /// **'Following team'**
  String get s_9f8a384d1fa2;

  /// No description provided for @s_e3a6fe565c7f.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get s_e3a6fe565c7f;

  /// No description provided for @s_02001a20e366.
  ///
  /// In en, this message translates to:
  /// **'Followed drivers'**
  String get s_02001a20e366;

  /// No description provided for @s_3f8a859aed64.
  ///
  /// In en, this message translates to:
  /// **'Followed teams'**
  String get s_3f8a859aed64;

  /// No description provided for @s_da16b9eb5a99.
  ///
  /// In en, this message translates to:
  /// **'No drivers followed yet.'**
  String get s_da16b9eb5a99;

  /// No description provided for @s_ae9f27c54900.
  ///
  /// In en, this message translates to:
  /// **'No teams followed yet.'**
  String get s_ae9f27c54900;

  /// No description provided for @s_a99dc7b725ff.
  ///
  /// In en, this message translates to:
  /// **'Choose drivers and teams from race results.'**
  String get s_a99dc7b725ff;

  /// No description provided for @s_6a5b7ed71337.
  ///
  /// In en, this message translates to:
  /// **'Spoiler-free mode'**
  String get s_6a5b7ed71337;

  /// No description provided for @s_72dee1be1e9c.
  ///
  /// In en, this message translates to:
  /// **'Hide completed-session results until you reveal them.'**
  String get s_72dee1be1e9c;

  /// No description provided for @s_b07dfea4c7fe.
  ///
  /// In en, this message translates to:
  /// **'Race completed'**
  String get s_b07dfea4c7fe;

  /// No description provided for @s_eb698cc145d1.
  ///
  /// In en, this message translates to:
  /// **'Results hidden'**
  String get s_eb698cc145d1;

  /// No description provided for @s_616ccc85f33d.
  ///
  /// In en, this message translates to:
  /// **'Reveal results'**
  String get s_616ccc85f33d;

  /// No description provided for @s_151840a05dd0.
  ///
  /// In en, this message translates to:
  /// **'Reveal this session'**
  String get s_151840a05dd0;

  /// No description provided for @s_10b7e93b7bcc.
  ///
  /// In en, this message translates to:
  /// **'Session times have not been published.'**
  String get s_10b7e93b7bcc;

  /// No description provided for @s_a0a2d3fab023.
  ///
  /// In en, this message translates to:
  /// **'Source: Jolpica F1'**
  String get s_a0a2d3fab023;

  /// No description provided for @s_2cacf414b165.
  ///
  /// In en, this message translates to:
  /// **'Race starts in'**
  String get s_2cacf414b165;

  /// No description provided for @s_15a027b504bd.
  ///
  /// In en, this message translates to:
  /// **'Scheduled start reached'**
  String get s_15a027b504bd;

  /// No description provided for @s_befa2c7789f1.
  ///
  /// In en, this message translates to:
  /// **'Loading races'**
  String get s_befa2c7789f1;

  /// No description provided for @s_f1d56f5b3642.
  ///
  /// In en, this message translates to:
  /// **'Unable to load races'**
  String get s_f1d56f5b3642;

  /// No description provided for @s_563862b7d73e.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get s_563862b7d73e;

  /// No description provided for @s_9f5cd8a2e880.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get s_9f5cd8a2e880;

  /// No description provided for @s_56e3badc4e6c.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get s_56e3badc4e6c;

  /// No description provided for @s_f2f8570ddd7b.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get s_f2f8570ddd7b;

  /// No description provided for @s_4e5126cbbdcc.
  ///
  /// In en, this message translates to:
  /// **'Showing saved schedule. Times may have changed.'**
  String get s_4e5126cbbdcc;

  /// No description provided for @s_3a29bb52a344.
  ///
  /// In en, this message translates to:
  /// **'Showing saved race summaries. Results may have changed.'**
  String get s_3a29bb52a344;

  /// No description provided for @s_572c7f8d8a5d.
  ///
  /// In en, this message translates to:
  /// **'No published races yet. Check back for the next schedule.'**
  String get s_572c7f8d8a5d;

  /// No description provided for @s_5f12aafe3cbe.
  ///
  /// In en, this message translates to:
  /// **'Coming later'**
  String get s_5f12aafe3cbe;

  /// No description provided for @s_b7467243fdfb.
  ///
  /// In en, this message translates to:
  /// **'Driver insights, with the original sources.'**
  String get s_b7467243fdfb;

  /// No description provided for @s_a9968cbf6453.
  ///
  /// In en, this message translates to:
  /// **'Interview summaries will arrive after the race database is ready.'**
  String get s_a9968cbf6453;

  /// No description provided for @s_5e241e54398e.
  ///
  /// In en, this message translates to:
  /// **'Follow what changes on the cars.'**
  String get s_5e241e54398e;

  /// No description provided for @s_e398417e0944.
  ///
  /// In en, this message translates to:
  /// **'Verified upgrade timelines come first. Interactive car models follow.'**
  String get s_e398417e0944;

  /// No description provided for @s_f7fa196097d1.
  ///
  /// In en, this message translates to:
  /// **'FP1'**
  String get s_f7fa196097d1;

  /// No description provided for @s_ea8772854374.
  ///
  /// In en, this message translates to:
  /// **'FP2'**
  String get s_ea8772854374;

  /// No description provided for @s_abb0ee629528.
  ///
  /// In en, this message translates to:
  /// **'FP3'**
  String get s_abb0ee629528;

  /// No description provided for @s_13301ff39aa5.
  ///
  /// In en, this message translates to:
  /// **'Qualifying'**
  String get s_13301ff39aa5;

  /// No description provided for @s_8ca15484a6a5.
  ///
  /// In en, this message translates to:
  /// **'Sprint'**
  String get s_8ca15484a6a5;

  /// No description provided for @s_365b72bf2c41.
  ///
  /// In en, this message translates to:
  /// **'Sprint Qualifying'**
  String get s_365b72bf2c41;

  /// No description provided for @s_6643dce8e4d3.
  ///
  /// In en, this message translates to:
  /// **'Race'**
  String get s_6643dce8e4d3;

  /// No description provided for @s_b2ebbec38d60.
  ///
  /// In en, this message translates to:
  /// **'Australian Grand Prix'**
  String get s_b2ebbec38d60;

  /// No description provided for @s_548778689826.
  ///
  /// In en, this message translates to:
  /// **'Chinese Grand Prix'**
  String get s_548778689826;

  /// No description provided for @s_9e7e9e3d2a23.
  ///
  /// In en, this message translates to:
  /// **'Japanese Grand Prix'**
  String get s_9e7e9e3d2a23;

  /// No description provided for @s_6fdc2bdb115e.
  ///
  /// In en, this message translates to:
  /// **'Bahrain Grand Prix'**
  String get s_6fdc2bdb115e;

  /// No description provided for @s_ca9dc945daff.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabian Grand Prix'**
  String get s_ca9dc945daff;

  /// No description provided for @s_a89d6b27ae47.
  ///
  /// In en, this message translates to:
  /// **'Miami Grand Prix'**
  String get s_a89d6b27ae47;

  /// No description provided for @s_3a4cba0b8404.
  ///
  /// In en, this message translates to:
  /// **'Canadian Grand Prix'**
  String get s_3a4cba0b8404;

  /// No description provided for @s_b3de061a4a97.
  ///
  /// In en, this message translates to:
  /// **'Monaco Grand Prix'**
  String get s_b3de061a4a97;

  /// No description provided for @s_a03199e86268.
  ///
  /// In en, this message translates to:
  /// **'Spanish Grand Prix'**
  String get s_a03199e86268;

  /// No description provided for @s_95b2c021ce64.
  ///
  /// In en, this message translates to:
  /// **'Austrian Grand Prix'**
  String get s_95b2c021ce64;

  /// No description provided for @s_f331b3e8cc56.
  ///
  /// In en, this message translates to:
  /// **'British Grand Prix'**
  String get s_f331b3e8cc56;

  /// No description provided for @s_58e3e77ecccd.
  ///
  /// In en, this message translates to:
  /// **'Belgian Grand Prix'**
  String get s_58e3e77ecccd;

  /// No description provided for @s_de92bdbca23e.
  ///
  /// In en, this message translates to:
  /// **'Hungarian Grand Prix'**
  String get s_de92bdbca23e;

  /// No description provided for @s_f3a19bc68fab.
  ///
  /// In en, this message translates to:
  /// **'Dutch Grand Prix'**
  String get s_f3a19bc68fab;

  /// No description provided for @s_6730aaeddc2e.
  ///
  /// In en, this message translates to:
  /// **'Italian Grand Prix'**
  String get s_6730aaeddc2e;

  /// No description provided for @s_a43bcc900bb4.
  ///
  /// In en, this message translates to:
  /// **'Azerbaijan Grand Prix'**
  String get s_a43bcc900bb4;

  /// No description provided for @s_5567e2cbc6da.
  ///
  /// In en, this message translates to:
  /// **'Singapore Grand Prix'**
  String get s_5567e2cbc6da;

  /// No description provided for @s_710b4fc651a2.
  ///
  /// In en, this message translates to:
  /// **'United States Grand Prix'**
  String get s_710b4fc651a2;

  /// No description provided for @s_ec4259297f8e.
  ///
  /// In en, this message translates to:
  /// **'Mexico City Grand Prix'**
  String get s_ec4259297f8e;

  /// No description provided for @s_5f90fc89cc68.
  ///
  /// In en, this message translates to:
  /// **'Mexican Grand Prix'**
  String get s_5f90fc89cc68;

  /// No description provided for @s_4f77e39cd1b7.
  ///
  /// In en, this message translates to:
  /// **'São Paulo Grand Prix'**
  String get s_4f77e39cd1b7;

  /// No description provided for @s_f4cb8a4818eb.
  ///
  /// In en, this message translates to:
  /// **'Brazilian Grand Prix'**
  String get s_f4cb8a4818eb;

  /// No description provided for @s_8e6381343ddb.
  ///
  /// In en, this message translates to:
  /// **'Las Vegas Grand Prix'**
  String get s_8e6381343ddb;

  /// No description provided for @s_fc7ae33fcf24.
  ///
  /// In en, this message translates to:
  /// **'Qatar Grand Prix'**
  String get s_fc7ae33fcf24;

  /// No description provided for @s_52e9f729ae3c.
  ///
  /// In en, this message translates to:
  /// **'Abu Dhabi Grand Prix'**
  String get s_52e9f729ae3c;

  /// No description provided for @s_e9bb6ccc0705.
  ///
  /// In en, this message translates to:
  /// **'Madrid Grand Prix'**
  String get s_e9bb6ccc0705;

  /// No description provided for @s_555f4be6dbec.
  ///
  /// In en, this message translates to:
  /// **'Emilia Romagna Grand Prix'**
  String get s_555f4be6dbec;

  /// No description provided for @s_4b200fc11771.
  ///
  /// In en, this message translates to:
  /// **'Baku City Circuit'**
  String get s_4b200fc11771;

  /// No description provided for @s_13f41a212961.
  ///
  /// In en, this message translates to:
  /// **'Shanghai International Circuit'**
  String get s_13f41a212961;

  /// No description provided for @s_dcbe988dc62e.
  ///
  /// In en, this message translates to:
  /// **'Suzuka Circuit'**
  String get s_dcbe988dc62e;

  /// No description provided for @s_a4cdfd457b24.
  ///
  /// In en, this message translates to:
  /// **'Marina Bay Street Circuit'**
  String get s_a4cdfd457b24;

  /// No description provided for @s_05c25ca961d0.
  ///
  /// In en, this message translates to:
  /// **'Circuit de Monaco'**
  String get s_05c25ca961d0;

  /// No description provided for @s_fa06660477ad.
  ///
  /// In en, this message translates to:
  /// **'Silverstone Circuit'**
  String get s_fa06660477ad;

  /// No description provided for @s_d2a673c6c6f5.
  ///
  /// In en, this message translates to:
  /// **'Albert Park Grand Prix Circuit'**
  String get s_d2a673c6c6f5;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
