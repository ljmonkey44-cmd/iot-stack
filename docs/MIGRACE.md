# Přechod z `docker run` na `docker compose`

Návod pro server, kde už stack běží z jednotlivých `docker run` příkazů.
Data v Postgresu, Node-REDu, Grafaně a Portaineru zůstanou zachovaná,
protože compose používá stejné názvy volumů.

> pgAdmin dřív neměl volume, takže se po přechodu přihlásíš údaji z `.env`
> a server `postgres` v něm zaregistruješ znovu (host `postgres`).

## 1. Repozitář na server

```bash
sudo apt install -y git
cd ~
git clone https://github.com/<uzivatel>/iot-stack.git
cd iot-stack
```

## 2. Hesla

```bash
cp .env.example .env
nano .env
```

- `POSTGRES_PASSWORD` – **současné** heslo Postgresu (to, které je v Node-REDu
  a Grafaně). Na existující databázi se tahle proměnná neuplatní, ale ať
  souhlasí pro případ nové instalace.
- `GRAFANA_ADMIN_PASSWORD` – současné heslo do Grafany (taky se uplatní jen
  u nové instalace).
- `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` – nové přihlášení do pgAdminu.

Uložení v nano: `Ctrl+O`, Enter, `Ctrl+X`.

## 3. Přenesení hesel Mosquitta

```bash
sudo cp -p ~/mosquitto/config/passwd ./mosquitto/config/passwd
sudo chown -R 1883:1883 mosquitto/config
sudo chmod 0700 mosquitto/config/passwd mosquitto/config/acl
```

## 4. Výměna kontejnerů

```bash
# zastaví a smaže staré kontejnery (volumy s daty zůstanou)
docker rm -f portainer nodered postgres pgadmin grafana mosquitto

# spustí celý stack
docker compose up -d
docker compose ps
```

Compose může vypsat varování, že volume „already exists but was not created
by Docker Compose“. To je v pořádku, použije stávající data.

## 5. Úklid

```bash
docker network rm iot        # stará ruční síť, compose má vlastní
rm -rf ~/mosquitto           # stará konfigurace, teď je v repozitáři
```

## 6. Kontrola

- `docker compose ps` – všech 6 služeb `running` / `healthy`
- Node-RED: uzel MQTT `connected`, žádné chyby u postgresql
- Grafana: dashboard ukazuje stará i nová data
- Deska: v `docker compose logs mosquitto` je vidět připojení `co2-sensor`
