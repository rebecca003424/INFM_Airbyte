-- Testdaten aus CSV-Dateien laden
-- COPY liest Dateien aus dem Container-Pfad /docker-entrypoint-initdb.d/data/

COPY fm_gebaeude (
    db_einfuegemarke, geb_nr, geb, geb2, baujahr, besitz, art, gebber_nr,
    hs_nr, qkz, fnw, pers_nr, denkmal_nr, ort_nr, stra_nr, haus_nr,
    gemark_nr, flur_nr, flurst_nr, miete, bauwerk, b_grad, l_grad, bem, text_geb, kurz_geb
)
FROM '/docker-entrypoint-initdb.d/data/fm_gebaeude.csv'
WITH (FORMAT CSV, NULL '');

COPY k_plz (
    db_einfuegemarke, plz, ueberkey, art, aikz, grokz, ort, krskfz, krs_astat, vv_bez
)
FROM '/docker-entrypoint-initdb.d/data/k_plz.csv'
WITH (FORMAT CSV, NULL '');

-- hso_students: pipe-delimited, with header, double-quoted fields
COPY hso_students (
    mtknr, firstname, surname, allfirstnames, academicTitle,
    dateofbirth, birthcity, country, gender, nationalityId, secondNationality,
    accounts, hochschulEmail, privateEmail, phone, currentSem,
    immaDat, exmaDat, exmaReason, studyStatus, universitysemester, kollegsemester,
    practicalsemester, leavesemester, stg_key, stg, fach, degree, poversion,
    fakultaet, stort, studentstatus, studysemester, curriculumsemester,
    progressvector, subjectfocus, h1_syncVers, dbversion, createdat, updatedat
)
FROM '/docker-entrypoint-initdb.d/data/hso_students.csv'
WITH (FORMAT CSV, DELIMITER '|', HEADER TRUE, QUOTE '"', NULL '');
