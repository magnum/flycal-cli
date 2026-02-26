# flycal-cli

CLI per accedere ai calendari Google da riga di comando.

## Installazione

```bash
gem install flycal-cli
```

Oppure aggiungi al tuo Gemfile:

```ruby
gem "flycal-cli"
```

## Configurazione iniziale

Prima di usare flycal, devi creare credenziali OAuth nel Google Cloud Console:

1. Vai su [Google Cloud Console - Credenziali](https://console.cloud.google.com/apis/credentials)
2. Crea un progetto (o usa uno esistente)
3. Abilita l'**API Google Calendar** (API e servizi → Libreria → Cerca "Google Calendar API")
4. Crea credenziali **Applicazione desktop** (OAuth 2.0 Client IDs)
5. Aggiungi questo URI come redirect autorizzato:
   ```
   http://127.0.0.1:9292/oauth2callback
   ```
6. Scarica il file JSON e salvalo come `~/.flycal/credentials.json`

## Comandi

### `flycal login`

Connetti al tuo account Google. Se non sei connesso, verrà generato un link da aprire nel browser per completare l'autenticazione OAuth.

```bash
flycal login
```

### `flycal calendars`

Mostra la lista dei calendari disponibili e permette di selezionare il calendario di default. La selezione è scorrevole (usa le frecce per navigare).

```bash
flycal calendars
```

### `flycal logout`

Disconnetti dall'account Google.

```bash
flycal logout
```

### `flycal search`

Cerca eventi nei calendari.

```bash
flycal search --from 2025-02-01 --to 2025-02-28
flycal search -f 2025-02-01 -t 2025-02-28 --description "riunione"
flycal search -f 2025-02-01T09:00 -t 2025-02-28T18:00 -c "Lavoro"
```

Opzioni:
- `-f, --from`: Data/ora inizio (es. `2025-01-01` o `2025-01-01T09:00`)
- `-t, --to`: Data/ora fine
- `-c, --calendar`: Nome o ID del calendario (default: calendario impostato con `flycal calendars`)
- `-d, --description`: Filtra eventi per testo nella descrizione

## File di configurazione

I dati vengono salvati in `~/.flycal/`:

- `config.yml` - calendario di default (`calendar_default`)
- `credentials.json` - credenziali OAuth (da creare manualmente)
- `tokens.yml` - token di accesso (gestito automaticamente)

## Pubblicazione su RubyGems

### Primo caricamento

1. Crea un account su [rubygems.org](https://rubygems.org) se non ce l'hai
2. Aggiorna `flycal-cli.gemspec` con i tuoi dati (autori, email, homepage)
3. Build e push:

```bash
# Build della gem
gem build flycal-cli.gemspec

# Push (ti chiederà email e password RubyGems)
gem push flycal-cli-0.1.0.gem
```

### Versioni successive

1. Aggiorna la versione in `lib/flycal_cli/version.rb`
2. Commit e tag:

```bash
git add .
git commit -m "Release v0.2.0"
git tag v0.2.0
git push origin main
git push origin v0.2.0
```

3. Build e push:

```bash
gem build flycal-cli.gemspec
gem push flycal-cli-0.2.0.gem
```

### Usando `rake release` (raccomandato)

Aggiungi al Rakefile:

```ruby
require "bundler/gem_tasks"
```

Poi:

```bash
# Per la prima release
bundle exec rake release

# Per release successive: aggiorna VERSION e poi
bundle exec rake release
```

`rake release` esegue: build, push su RubyGems, commit, tag e push su git.

## Licenza

MIT
