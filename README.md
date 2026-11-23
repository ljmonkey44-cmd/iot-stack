# IoT Stack – měření kvality vzduchu v cloudu

Kompletní IoT řetězec od senzoru po dashboard: ESP32 měří CO₂, teplotu a vlhkost,
posílá je přes MQTT do cloudu, Node-RED je zpracuje a uloží do PostgreSQL
a Grafana z nich kreslí živé dashboardy.

![Dashboard](docs/dashboard.png)

Celý serverový stack běží v Dockeru na jednom virtuálním serveru (Google Cloud,
Ubuntu 24.04 LTS) a spouští se jedním příkazem.

## Architektura

```mermaid
flowchart LR
    U["Prohlížeč"]

    subgraph Domov
        S["ESP32-S3 + SCD41<br/>(Stolní společník)"]
        HA["Home Assistant<br/>(lokální MQTT)"]
    end

    subgraph Cloud["Google Cloud VM · Docker"]
        M["Mosquitto<br/>MQTT broker"]
        N["Node-RED<br/>zpracování"]
        P[("PostgreSQL<br/>iot_db")]
        C["Caddy<br/>HTTPS proxy"]
        G["Grafana<br/>dashboardy"]
        A["pgAdmin"]
        PT["Portainer"]
    end

    S -- "MQTT · LAN" --> HA
    S -- "MQTT · internet :1883" --> M
    M -- "home/#" --> N
    N -- "INSERT" --> P
    P --> G
    P --> A
    U -- "HTTPS :443" --> C
    C --> G
```

Zařízení má dvě nezávislá MQTT spojení: jedno do lokálního Home Assistantu
(ovládání, automatizace) a druhé do cloudu (dlouhodobé ukládání a analýza).
Spojení do cloudu navazuje vždy zařízení, takže doma není potřeba otevírat
žádné porty.

## Komponenty

| Služba     | K čemu                                  | Port   | Dostupnost |
|------------|-----------------------------------------|--------|------------|
| Mosquitto  | MQTT broker, příjem dat ze zařízení     | 1883   | internet (heslo + ACL) |
| Caddy      | reverse proxy, automatický HTTPS certifikát | 80, 443 | internet |
| Grafana    | dashboardy a vizualizace                | 3000   | jen přes Caddy (HTTPS + přihlášení) |
| Node-RED   | zpracování zpráv a zápis do DB          | 1880   | jen SSH tunel |
| pgAdmin    | webová správa databáze                  | 5050   | jen SSH tunel |
| Portainer  | webová správa Docker kontejnerů         | 9443   | jen SSH tunel |
| PostgreSQL | ukládání měření                         | 5432   | jen interní Docker síť |

## Datový kontrakt

**MQTT topicy**

| Topic                     | Směr      | Obsah |
|---------------------------|-----------|-------|
| `home/co2-sensor/state`   | zařízení → cloud | JSON s měřením, každých 30 s |
| `home/co2-sensor/status`  | zařízení → cloud | `online` / `offline` (LWT) |

**Payload**

```json
{"device":"co2-sensor","co2":650,"temperature":22.4,"humidity":48.1}
```

**Tabulka `sensor_data`** (viz [`db/init/01_schema.sql`](db/init/01_schema.sql))

| Sloupec       | Typ         | Popis |
|---------------|-------------|-------|
| `id`          | SERIAL      | primární klíč |
| `ts`          | TIMESTAMPTZ | čas příjmu (doplní DB, UTC) |
| `device`      | TEXT        | identifikátor zařízení |
| `temperature` | REAL        | °C |
| `humidity`    | REAL        | % RH |
| `co2`         | REAL        | ppm |

Čas doplňuje databáze při zápisu, protože zařízení nemá přesné hodiny.

## Instalace od nuly

### 1. Server

- VM s Ubuntu 24.04 LTS (stačí e2-small: 2 vCPU, 2 GB RAM, 20 GB disk)
- Ve firewallu povolené příchozí TCP porty: `22, 80, 443, 1883` (nic dalšího!)
- Doména, která ukazuje na IP serveru (stačí zdarma, např. [DuckDNS](https://www.duckdns.org))
- Docker:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER   # pak se odhlásit a znovu přihlásit
```

- Doporučený swap (při 2 GB RAM):

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 2. Repozitář a hesla

```bash
git clone https://github.com/ljmonkey44-cmd/iot-stack.git
cd iot-stack
cp .env.example .env
nano .env          # doplnit DOMAIN a hesla (openssl rand -hex 12)
```

### 3. Uživatelé MQTT

```bash
docker run --rm -v ./mosquitto/config:/mosquitto/config eclipse-mosquitto:2 \
  mosquitto_passwd -c -b /mosquitto/config/passwd co2-sensor 'HESLO_ZARIZENI'
docker run --rm -v ./mosquitto/config:/mosquitto/config eclipse-mosquitto:2 \
  mosquitto_passwd -b /mosquitto/config/passwd nodered 'HESLO_NODERED'

sudo chown -R 1883:1883 mosquitto/config
sudo chmod 0600 mosquitto/config/passwd
```

### 4. Spuštění

```bash
docker compose up -d
docker compose ps
docker compose logs caddy | grep -i "certificate obtained"   # HTTPS certifikát
```

Grafana je pak dostupná na `https://DOMENA` (Caddy si certifikát
od Let's Encrypt vyřídí a obnovuje sám).

### 5. Přístup k administraci (SSH tunel)

Node-RED, pgAdmin a Portainer poslouchají jen na `127.0.0.1` serveru,
takže z internetu nejsou vidět. Připojíš se k nim přes SSH tunel:

```powershell
ssh -i ~/.ssh/gcp_key -L 1880:localhost:1880 -L 5050:localhost:5050 -L 9443:localhost:9443 uzivatel@IP
```

Pohodlnější je uložit si tunel do `~/.ssh/config` a připojovat se jen `ssh iot`:

```
Host iot
    HostName IP_SERVERU
    User uzivatel
    IdentityFile ~/.ssh/gcp_key
    LocalForward 1880 localhost:1880
    LocalForward 5050 localhost:5050
    LocalForward 9443 localhost:9443
```

Dokud je okno otevřené, fungují v prohlížeči:
`http://localhost:1880` (Node-RED), `http://localhost:5050` (pgAdmin),
`https://localhost:9443` (Portainer).

### 6. Konfigurace v aplikacích

- **Portainer** (`https://localhost:9443`) – do 5 minut od startu vytvořit admin účet.
- **Node-RED** (`http://localhost:1880`) – nainstalovat `node-red-contrib-postgresql`
  a importovat flow ze složky [`nodered/`](nodered/).
  Připojení: MQTT broker `mosquitto:1883` (uživatel `nodered`),
  databáze `postgres:5432 / iot_db` (uživatel `postgres`, SSL vypnuto).
- **Grafana** (`https://DOMENA`) – přidat data source PostgreSQL
  (`postgres:5432`, `iot_db`, SSL `disable`) a importovat dashboard
  ze složky [`grafana/dashboards/`](grafana/dashboards/).
- **pgAdmin** (`http://localhost:5050`) – zaregistrovat server s hostem `postgres`.

## Užitečné příkazy

```bash
docker compose ps                     # stav služeb
docker compose logs -f mosquitto      # logy konkrétní služby
docker compose restart nodered        # restart služby
docker compose pull && docker compose up -d   # aktualizace image

# živé sledování MQTT zpráv
docker exec mosquitto mosquitto_sub -u nodered -P 'HESLO' -t 'home/#' -v

# záloha databáze
docker exec postgres pg_dump -U postgres iot_db > backup_$(date +%F).sql
```

## Bezpečnost

- Všechna hesla jsou v `.env` a `mosquitto/config/passwd`, oba soubory
  jsou v `.gitignore`.
- MQTT bez anonymního přístupu, každé zařízení má vlastního uživatele
  a ACL omezuje zápis jen do jeho topicu.
- PostgreSQL není publikovaný vůbec, Node-RED, pgAdmin a Portainer jen na
  localhost (přístup přes SSH tunel). Do internetu jsou otevřené jen
  MQTT, SSH a Caddy (80/443).
- Grafana je dostupná jen přes HTTPS (Caddy + Let's Encrypt), přihlašovací
  údaje tak neputují internetem v čitelné podobě.
- Poučení z reálného incidentu: [`docs/INCIDENT.md`](docs/INCIDENT.md).

## Další rozvoj

- [ ] TLS pro MQTT (port 8883) – firmware je připravený
- [x] Doména a HTTPS (Let's Encrypt) pro Grafanu
- [ ] Data z Aqara FP2 (přítomnost) přes Home Assistant `mqtt_statestream`
- [ ] TimescaleDB pro efektivní práci s časovými řadami
- [ ] Panel online/offline stavu zařízení

## Autor

Bc. Lukáš Jůza – ČZU v Praze, PEF, Informatika
