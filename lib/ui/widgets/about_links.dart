import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_version.dart';
import '../../i18n.dart';
import '../screens/auth_screens.dart' show openPage;
import '../theme.dart';

/// Adres voor vragen en hulp.
const supportEmail = 'support@macromatrix.eu';

/// Een link openen. Te vervangen in tests (daar opent niets).
@visibleForTesting
Future<void> Function(String target) openAboutLink = (target) async {
  if (target.startsWith('mailto:')) {
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  } else {
    await openPage(target);
  }
};

/// Onderaan Instellingen: privacybeleid, voorwaarden, account verwijderen (webpagina), contact en de versie. Ook
/// bereikbaar als je ingelogd bent (Google Play wil het privacybeleid in de app zelf, GP-5).
class AboutLinks extends StatelessWidget {
  const AboutLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget link(String key, IconData icon, String label, String target, {String? sub}) => ListTile(
      key: ValueKey('about-$key'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20, color: pal.ink2),
      title: Text(label, style: TextStyle(fontSize: 14, color: pal.ink)),
      subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: pal.ink3)),
      trailing: Icon(Icons.open_in_new_rounded, size: 16, color: pal.ink3),
      onTap: () => openAboutLink(target),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        link('privacy', Icons.privacy_tip_outlined, tr('Privacy policy', 'Privacybeleid'), '/privacy/'),
        link('terms', Icons.description_outlined, tr('Terms of use', 'Gebruiksvoorwaarden'), '/terms/'),
        link('delete', Icons.person_remove_outlined, tr('How to delete your account', 'Je account verwijderen'), '/delete-account/'),
        link('contact', Icons.mail_outline_rounded, tr('Contact', 'Contact'), 'mailto:$supportEmail', sub: supportEmail),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            tr('MacroMatrix version $appVersion', 'MacroMatrix versie $appVersion'),
            key: const ValueKey('about-version'),
            style: TextStyle(fontSize: 12, color: pal.ink3),
          ),
        ),
      ],
    );
  }
}
