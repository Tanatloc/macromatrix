# Mailtemplates (Engels)

`python make.py` maakt de HTML-bestanden en `templates.json` (onderwerp + inhoud per template).

Toepassen met een Supabase-toegangstoken (nooit in git of in een bestand bewaren):

```sh
curl -X PATCH -H "Authorization: Bearer <sbp_token>" -H "Content-Type: application/json" \
  --data @templates.json https://api.supabase.com/v1/projects/hvqbqgxpksxmavopngap/config/auth
```

Of met de hand: *Authentication* → *Emails* → *Templates*, per template het onderwerp en de HTML uit het bestand.
Het logo bovenaan komt van https://app.divinenet.online/assets/img/logo-112.png (site/assets/img).
