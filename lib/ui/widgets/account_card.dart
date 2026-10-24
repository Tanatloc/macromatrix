import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../sync/account.dart';
import '../screens/auth_screens.dart';
import '../theme.dart';
import 'kit.dart';
import '../../i18n.dart';

/// Account in Profiel: e-mail, synchronisatie, wachtwoord wijzigen, uitloggen en account verwijderen.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (done != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      _message = authMessage(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changePassword(Account a) async {
    final pw = TextEditingController(), pw2 = TextEditingController();
    String? problem;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Change password', 'Wachtwoord wijzigen')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: pw,
                obscureText: true,
                autofillHints: kIsWeb ? null : const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: tr('New password', 'Nieuw wachtwoord')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw2,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Repeat the password', 'Herhaal het wachtwoord')),
              ),
              const SizedBox(height: 8),
              Text(
                problem ?? tr('At least 8 characters, with letters and numbers.', 'Minstens 8 tekens, met letters en cijfers.'),
                style: TextStyle(fontSize: 12, color: problem == null ? ctx.pal.ink3 : ctx.pal.high),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(
              onPressed: () {
                final p =
                    passwordProblem(pw.text) ??
                    (pw.text == pw2.text ? null : tr('The two passwords do not match.', 'De twee wachtwoorden zijn niet gelijk.'));
                if (p != null) return setD(() => problem = p);
                Navigator.pop(ctx, true);
              },
              child: Text(tr('Save', 'Opslaan')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _run(() => a.changePassword(pw.text), done: tr('Your password has been changed.', 'Je wachtwoord is gewijzigd.'));
    pw.dispose();
    pw2.dispose();
  }

  Future<void> _signOut(Account a) async {
    final ok = await a.signOut();
    if (ok || !mounted) return;
    final force = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Not everything has been sent yet', 'Nog niet alles is verstuurd')),
        content: Text(
          tr(
            'Some changes are not on the server yet (no connection?). If you log out now, you will lose them. '
                'Better try again with internet.',
            'Er zijn wijzigingen die nog niet op de server staan (geen verbinding?). Als je nu uitlogt, ben je die kwijt. '
                'Probeer het liever opnieuw met internet.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.pal.high),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Log out anyway', 'Toch uitloggen')),
          ),
        ],
      ),
    );
    if (force == true) await a.signOut(force: true);
  }

  Future<void> _delete(Account a) async {
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Delete account?', 'Account verwijderen?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Your account and all your data will be permanently deleted, also on your other devices. This cannot be undone.',
                  'Je account en al je gegevens worden definitief gewist, ook op je andere toestellen. Dit kan niet ongedaan worden.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                decoration: InputDecoration(labelText: tr('Type DELETE to confirm', 'Typ VERWIJDEREN om te bevestigen')),
                onChanged: (_) => setD(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ctx.pal.high),
              onPressed: confirm.text.trim().toUpperCase() == tr('DELETE', 'VERWIJDEREN') ? () => Navigator.pop(ctx, true) : null,
              child: Text(tr('Delete permanently', 'Definitief verwijderen')),
            ),
          ],
        ),
      ),
    );
    confirm.dispose();
    if (ok == true) await _run(a.deleteAccount);
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Account>();
    final p = context.pal;

    if (Account.configured && !a.signedIn && a.localOnly) return const GuestAccountPanel();

    if (!Account.configured || !a.signedIn) {
      return Panel(
        shadow: false,
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: p.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(
                  'This version works without an account: your data stays on this device only.',
                  'Deze versie werkt zonder account: je gegevens staan alleen op dit toestel.',
                ),
                style: TextStyle(fontSize: 13, height: 1.45, color: p.ink2),
              ),
            ),
          ],
        ),
      );
    }

    final last = a.lastSync;
    final (icon, color, status) = switch (a.status) {
      SyncStatus.syncing => (Icons.sync_rounded, p.brand, tr('Syncing…', 'Bezig met synchroniseren…')),
      SyncStatus.offline => (
        Icons.cloud_off_outlined,
        p.ink3,
        tr('No connection: changes will be sent later', 'Geen verbinding: wijzigingen worden later verstuurd'),
      ),
      SyncStatus.error => (Icons.error_outline_rounded, p.high, a.error ?? tr('Sync failed', 'Synchroniseren lukte niet')),
      SyncStatus.idle => (
        Icons.cloud_done_outlined,
        p.ok,
        last == null ? tr('Not synced yet', 'Nog niet gesynchroniseerd') : tr('Synced ${_when(last)}', 'Gesynchroniseerd ${_when(last)}'),
      ),
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelTitle('Account'),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: p.brandSoft,
                child: Text(
                  (a.email ?? '?').substring(0, 1).toUpperCase(),
                  style: TextStyle(color: p.brand, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.email ?? '',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(status, style: TextStyle(fontSize: 12, color: color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    'Automatic: after every change, and what you do on another device shows up here within seconds.',
                    'Gaat vanzelf: na elke wijziging, en wat je op een ander toestel doet, verschijnt hier binnen enkele seconden.',
                  ),
                  style: TextStyle(fontSize: 12, height: 1.4, color: p.ink3),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                onPressed: a.status == SyncStatus.syncing ? null : a.sync,
                child: Text(tr('Now', 'Nu')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: _busy ? null : () => _changePassword(a), child: Text(tr('Change password', 'Wachtwoord wijzigen'))),
              OutlinedButton(onPressed: _busy ? null : () => _signOut(a), child: Text(tr('Log out', 'Uitloggen'))),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: p.high, padding: EdgeInsets.zero),
              onPressed: _busy ? null : () => _delete(a),
              child: Text(tr('Delete account', 'Account verwijderen')),
            ),
          ),
          if (_message != null) Text(_message!, style: TextStyle(fontSize: 12.5, color: p.high)),
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? tr('at ', 'om ') + DateFormat('HH:mm').format(t) : tr('on ', 'op ') + DateFormat('d MMM, HH:mm', appLocale).format(t);
  }
}

/// Zonder account: waar je gegevens staan, en een account maken of inloggen. Je blijft gast tot dat lukt; daarna
/// gaat alles mee naar het account (zie [Account] en [UserDb.yieldUnsentSettings]).
class GuestAccountPanel extends StatelessWidget {
  const GuestAccountPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    void open(bool register) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuthScreen(register: register)));
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(runsOnWeb ? Icons.web_rounded : Icons.phone_android_rounded, color: p.ink3),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  runsOnWeb
                      ? tr(
                          'You use MacroMatrix without an account. Your data is kept in this browser only; create a free account to keep it safe and use it on your phone. What you logged comes along.',
                          'Je gebruikt MacroMatrix zonder account. Je gegevens blijven alleen in deze browser; maak een gratis account om ze veilig te bewaren en ze op je gsm te gebruiken. Wat je logde, gaat mee.',
                        )
                      : tr(
                          'You use MacroMatrix without an account: your data is only on this device. Create a free account to sync between devices, back up your data and add friends. What you logged comes along.',
                          'Je gebruikt MacroMatrix zonder account: je gegevens staan alleen op dit toestel. Maak een gratis account om te synchroniseren, een back-up te hebben en vrienden toe te voegen. Wat je logde, gaat mee.',
                        ),
                  style: TextStyle(fontSize: 13, height: 1.45, color: p.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton(onPressed: () => open(true), child: Text(tr('Create free account', 'Gratis account maken'))),
              OutlinedButton(onPressed: () => open(false), child: Text(tr('Log in', 'Inloggen'))),
            ],
          ),
        ],
      ),
    );
  }
}
