"""Engelse mailsjablonen voor Supabase (tabellen en inline-stijlen, zodat ze in elke mailapp goed ogen).
Gebruik: python make.py   -> schrijft de .html-bestanden en templates.json (onderwerpen + inhoud voor de API)."""
import json

LOGO = 'https://app.divinenet.online/assets/img/logo-112.png'
FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"


def mail(title, intro, code=True, note=None, outro="Didn't ask for this? You can safely ignore this email."):
    code_html = f'''
          <tr><td style="padding:24px 0 6px">
            <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:#F4F3EF;border:1px solid #E4E1DA;border-radius:14px">
              <tr><td align="center" style="padding:22px 12px">
                <div style="font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:36px;font-weight:700;letter-spacing:10px;color:#15171A">{{{{ .Token }}}}</div>
                <div style="font-family:{FONT};font-size:13px;color:#676C75;padding-top:8px">Valid for 15 minutes</div>
              </td></tr>
            </table>
          </td></tr>''' if code else ''
    note_html = f'''
          <tr><td style="padding:18px 0 0;font-family:{FONT};font-size:15px;line-height:1.55;color:#4B5058">{note}</td></tr>''' if note else ''
    return f'''<!doctype html>
<html><body style="margin:0;padding:0;background:#F4F3EF">
<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:#F4F3EF">
  <tr><td align="center" style="padding:32px 16px">
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:480px;background:#FFFFFF;border:1px solid #E4E1DA;border-radius:20px;overflow:hidden">
      <tr><td style="background:#0D0F11;padding:22px 28px">
        <table role="presentation" cellpadding="0" cellspacing="0"><tr>
          <td style="padding-right:12px"><img src="{LOGO}" width="40" height="40" alt="" style="display:block;border-radius:10px"></td>
          <td style="font-family:{FONT};font-size:18px;font-weight:700;color:#ECEDEF">MacroMatrix</td>
        </tr></table>
      </td></tr>
      <tr><td style="font-size:0;line-height:0;height:4px">
        <table role="presentation" cellpadding="0" cellspacing="0" width="100%"><tr>
          <td width="38%" style="background:#8FA3FF;height:4px"></td><td width="37%" style="background:#E3A956;height:4px"></td><td width="25%" style="background:#E08BAA;height:4px"></td>
        </tr></table>
      </td></tr>
      <tr><td style="padding:30px 28px 30px">
        <table role="presentation" cellpadding="0" cellspacing="0" width="100%">
          <tr><td style="font-family:{FONT};font-size:24px;font-weight:700;letter-spacing:-0.3px;color:#15171A;padding-bottom:10px">{title}</td></tr>
          <tr><td style="font-family:{FONT};font-size:16px;line-height:1.55;color:#4B5058">{intro}</td></tr>{code_html}{note_html}
          <tr><td style="padding-top:22px;border-bottom:1px solid #E4E1DA"></td></tr>
          <tr><td style="padding-top:18px;font-family:{FONT};font-size:14px;line-height:1.55;color:#676C75">{outro}</td></tr>
        </table>
      </td></tr>
    </table>
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:480px">
      <tr><td align="center" style="padding:18px 8px 0;font-family:{FONT};font-size:12px;line-height:1.6;color:#8B919A">
        MacroMatrix by DivineNet · <a href="https://app.divinenet.online" style="color:#8B919A">app.divinenet.online</a><br>
        You get this email because of an action on your MacroMatrix account.
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>
'''


T = {
    'confirmation': ('Your MacroMatrix code: {{ .Token }}', 'confirm-signup.html',
                     mail('Welcome to MacroMatrix', 'Type this code in the app to confirm your email address and get started:',
                          note='Next, you tell us a little about yourself and we calculate your personal targets for all 69 nutrients.')),
    'magic_link': ('Your MacroMatrix login code: {{ .Token }}', 'magic-link.html',
                   mail('Your login code', 'Type this code in the app to log in:')),
    'recovery': ('Choose a new MacroMatrix password', 'reset-password.html',
                 mail('Choose a new password', 'Type this code in the app to choose a new password:',
                      outro="Didn't ask for a new password? Then you can ignore this email; your password stays the same.")),
    'email_change': ('Confirm your new email for MacroMatrix', 'change-email.html',
                     mail('Confirm your new email', 'Type this code in the app to confirm <b>{{ .NewEmail }}</b> as your new email address:')),
    'reauthentication': ('Your MacroMatrix verification code: {{ .Token }}', 'reauthentication.html',
                         mail('Confirm it is you', 'Type this code in the app to confirm this action:')),
    'password_changed_notification': ('Your MacroMatrix password was changed', 'password-changed.html',
                                      mail('Your password was changed', 'The password of your MacroMatrix account ({{ .Email }}) was just changed.', code=False,
                                           outro="Was this you? Then you don't need to do anything.<br>Wasn't it you? Choose a new password right away in the app via <b>Forgot password</b>, and email us at <a href=\"mailto:privacy@divinenet.online\" style=\"color:#0E6B65\">privacy@divinenet.online</a>.")),
}
api = {}
for key, (subject, fname, html) in T.items():
    open(fname, 'w').write(html)
    api[f'mailer_subjects_{key}'] = subject
    api[f'mailer_templates_{key}_content'] = html
json.dump(api, open('templates.json', 'w'), indent=1)
