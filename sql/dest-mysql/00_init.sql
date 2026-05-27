-- dest-mysql Initialisierung
-- Laeuft automatisch beim ersten Container-Start (leeres Volume).
-- Stellt sicher, dass destuser alle noetigen Rechte hat
-- und die Datenbank UTF-8 verwendet.

-- local_infile aktivieren (benoetigt von Airbyte MySQL Destination Connector)
-- Dauerhaft via --local-infile=1 in docker-compose.yml gesetzt;
-- hier zur Sicherheit auch per SQL (laeuft als root).
SET GLOBAL local_infile = true;

-- Zeichensatz
ALTER DATABASE destdb
    CHARACTER SET  utf8mb4
    COLLATE        utf8mb4_unicode_ci;

-- Sicherstellen, dass destuser von jedem Host aus vollen Zugriff hat
-- (MySQL Docker-Image setzt dies ueber MYSQL_USER/MYSQL_DATABASE,
--  dieses Script dient als explizite Absicherung.)
GRANT ALL PRIVILEGES ON destdb.* TO 'destuser'@'%';
FLUSH PRIVILEGES;
