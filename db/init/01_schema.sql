-- Schéma pro měření ze senzorů.
-- Spouští se automaticky jen při prvním startu Postgresu (prázdný volume).

CREATE TABLE IF NOT EXISTS sensor_data (
  id          SERIAL PRIMARY KEY,
  ts          TIMESTAMPTZ NOT NULL DEFAULT now(),  -- čas příjmu (UTC)
  device      TEXT        NOT NULL,                -- např. 'co2-sensor'
  temperature REAL,                                -- °C
  humidity    REAL,                                -- % RH
  co2         REAL                                 -- ppm
);

-- Index pro typický dotaz Grafany: jedno zařízení v časovém rozsahu
CREATE INDEX IF NOT EXISTS sensor_data_device_ts_idx
  ON sensor_data (device, ts DESC);
