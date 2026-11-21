# Incident: kompromitace Node-RED (20.–21. 11. 2026)

## Shrnutí

Node-RED byl dostupný z internetu na portu 1880 **bez přihlášení**
(výchozí stav Node-RED). Automatizovaný útočník ho našel, nahradil
všechna flow vlastním a spustil v kontejneru škodlivý program.
Útok zůstal uvnitř kontejneru Node-RED. Server ani ostatní služby
zasaženy nebyly. Následkem byl výpadek zápisu dat přibližně na 15 hodin.

## Časová osa (UTC)

| Čas              | Událost |
|------------------|---------|
| 20. 11. 19:30:43 | poslední zapsané měření |
| 20. 11. 19:31:09 | útočník nasadil vlastní flow (`Updated flows` v logu) |
| 20. 11. 19:50, 20:24 | další nasazení flow útočníkem |
| 21. 11. ~10:30   | zjištěno: Grafana bez dat, v Node-RED cizí záložka „Persist“ |
| 21. 11. ~10:35   | Node-RED zastaven, port 1880 odebrán z firewallu |
| 21. 11. ~11:00   | obnova a změna hesel dokončena, data opět tečou |

## Co útočník udělal

- Smazal původní flow a vytvořil záložku „Persist“ s uzlem `exec`.
- Uzel spouštěl shellový příkaz, který:
  1. zjistil architekturu CPU (`uname -m`),
  2. stáhl odpovídající binárku z cizího serveru,
  3. nastavil jí právo ke spuštění a spustil ji,
  4. pokusil se zajistit přežití restartu přes `crontab`.
- `docker diff nodered` ukázal jediný přidaný soubor: `/tmp/.s`.
- Typický cíl: těžba kryptoměn nebo zapojení do botnetu.

## Rozsah dopadu

| Oblast | Stav |
|--------|------|
| Kontejner Node-RED | kompromitovaný, smazán i s volume |
| Hostitelský server | bez známek kompromitace (procesy, `/tmp`, cron) |
| PostgreSQL | bez podezřelých procesů ani spojení |
| Hesla uložená v Node-RED | považována za uniklá, změněna (Postgres, MQTT `nodered`) |
| Data | mezera v měřeních ~15 h, žádná ztráta starších dat |
| Zařízení (ESP32) | nezasaženo, používá jiného MQTT uživatele |

## Příčina

1. Node-RED ve výchozím stavu nemá žádné přihlášení.
2. Port 1880 byl ve firewallu otevřený pro `0.0.0.0/0`.
3. Boti nepřetržitě skenují internet a hledají právě takové služby.
   Od otevření portu do útoku uplynulo zhruba 30 hodin.

## Náprava

- Kontejner i volume Node-RED smazány, flow obnoveno z exportu v Gitu
  (z doby před útokem).
- Změněna hesla, která byla v Node-RED uložena.
- Node-RED, pgAdmin a Portainer publikované jen na `127.0.0.1`,
  přístup pouze přes SSH tunel.
- Firewall zúžen na `22, 1883, 3000`.

## Poučení

- **Administrační nástroje nepatří do internetu.** Nejen ty bez hesla.
  Bezpečný výchozí stav je „zavřeno“ a otevírá se jen to, co je nutné.
- **Výchozí nastavení není bezpečné nastavení.** Před otevřením portu
  ověřit, jestli služba vyžaduje přihlášení.
- **Kontejnery omezily dopad.** Útočník neměl přístup k hostiteli
  ani k Docker socketu, proto stačilo smazat jeden kontejner.
- **Infrastruktura jako kód se vyplatila.** Díky exportu flow v Gitu
  trvala obnova minuty.
- **Monitoring by útok odhalil dřív.** Další krok: upozornění,
  když do databáze delší dobu nepřijdou nová data.
