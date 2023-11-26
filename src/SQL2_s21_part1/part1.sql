-- Active: 1699327853942@@127.0.0.1@5432@s21_info

CREATE OR REPLACE DATABASE S21_Info;

CREATE TABLE IF NOT EXISTS  Peers(
    Nickname VARCHAR NOT NULL PRIMARY KEY,
    Birthday DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS TimeTracking(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer VARCHAR NOT NULL,
    "Date" DATE NOT NULL,
    "Time" TIME NOT NULL,
    "State" CHAR NOT NULL,
    CONSTRAINT ch_time_tracking_state CHECK ("State" IN ('1', '2')),
    CONSTRAINT fk_time_tracking_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname)  
);

CREATE TABLE IF NOT EXISTS Recommendations(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer VARCHAR NOT NULL,
    RecommendedPeer VARCHAR NOT NULL,
    CONSTRAINT fk_recommendations_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_recommendations_recommended_peer FOREIGN KEY(RecommendedPeer) REFERENCES Peers(Nickname),
    CONSTRAINT ch_recommendations_peer_recommended_peer CHECK (Peer != RecommendedPeer)
);

CREATE TABLE IF NOT EXISTS Friends(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer1 VARCHAR NOT NULL,
    Peer2 VARCHAR NOT NULL,
    CONSTRAINT fk_friends_peer1 FOREIGN KEY(Peer1) REFERENCES Peers(Nickname),
    CONSTRAINT fk_friends_peer2 FOREIGN KEY(Peer2) REFERENCES Peers(Nickname),
    CONSTRAINT ch_friends_peer1_peer2 CHECK (Peer1 != Peer2)
);

CREATE TABLE IF NOT EXISTS TransferredPoints(
    ID SERIAL NOT NULL PRIMARY KEY,
    CheckingPeer VARCHAR NOT NULL,
    CheckedPeer VARCHAR NOT NULL,
    PointsAmount INT NOT NULL DEFAULT 0,
    CONSTRAINT fk_transferred_points_checking_peer FOREIGN KEY(CheckingPeer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_transferred_points_checked_peer FOREIGN KEY(CheckedPeer) REFERENCES Peers(Nickname),
    CONSTRAINT ch_transferred_points_checking_peer_checked_peer CHECK (CheckingPeer != CheckedPeer)
);

CREATE TABLE IF NOT EXISTS  Tasks(
    Title VARCHAR NOT NULL PRIMARY KEY,
    ParentTask VARCHAR,
    MaxXP INT NOT NULL
);

CREATE TABLE IF NOT EXISTS Checks(
    ID SERIAL NOT NULL PRIMARY KEY, 
    Peer VARCHAR NOT NULL,
    Task VARCHAR NOT NULL,
    Date DATE NOT NULL,
    CONSTRAINT fk_checks_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_checks_task FOREIGN KEY(Task) REFERENCES Tasks(Title)
);

CREATE TABLE IF NOT EXISTS XP(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    XPAmount BIGINT NOT NULL,
    CONSTRAINT fk_xp_check FOREIGN KEY ("Check") REFERENCES Checks(ID),
    CONSTRAINT ch_xp_xp_amout CHECK (XPAmount >= 0) 
); 

CREATE TYPE check_status AS ENUM ('Start', 'Success', 'Failure');

CREATE TABLE IF NOT EXISTS Verter(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    "State" check_status NOT NULL,
    "Time" TIME NOT NULL,
    CONSTRAINT fk_verter_check FOREIGN KEY ("Check") REFERENCES Checks(ID)
); 

CREATE TABLE IF NOT EXISTS P2P(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    CheckingPeer VARCHAR NOT NULL, 
    "State" check_status NOT NULL,
    "Time" TIME NOT NULL,
    CONSTRAINT fk_p2p_check FOREIGN KEY ("Check") REFERENCES Checks(ID),
    CONSTRAINT fk_p2p_checking_peer FOREIGN KEY (CheckingPeer) REFERENCES Peers(Nickname)
); 

CREATE OR REPLACE FUNCTION fnc_trg_tasks_insert_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ParentTask IS NULL THEN
        IF EXISTS (
            SELECT Title FROM Tasks WHERE ParentTask IS NULL
        ) THEN RAISE EXCEPTION 'В таблице должно быть одно задание, у которого нет условия входа (т.е. поле ParentTask равно null)';
        END IF;
    ELSE
        IF NOT EXISTS (
            SELECT Title FROM Tasks WHERE ParentTask IS NULL
        ) THEN RAISE EXCEPTION 'В таблице еще нет корневого задание, у которого нет условия входа (т.е. поле ParentTask равно null)';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER trg_tasks_insert_update
BEFORE INSERT OR UPDATE ON Tasks
FOR EACH ROW
EXECUTE FUNCTION fnc_trg_tasks_insert_update();

CREATE OR REPLACE FUNCTION fnc_p2p_insert_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW."State" = 'Start' THEN
        IF EXISTS (
                SELECT "State" FROM P2P WHERE id = NEW.id AND "State" = 'Start'
            ) THEN RAISE EXCEPTION 'Проверка имеет уже статус Start';
        END IF;
    ELSE
        IF NEW."Time" <= (
                SELECT "Time" FROM P2P WHERE NEW."Check" = P2P."Check"
                ORDER BY "Time" DESC LIMIT 1           
            )
            THEN RAISE EXCEPTION 'Проверка не может быть завершена раньше, чем она начнется';
        END IF;
        IF NOT EXISTS (	
                SELECT * FROM P2P WHERE "Check" = NEW."Check" AND "State" = 'Start'
		    ) THEN RAISE EXCEPTION 'У проверки нет записи со статусом Start';
		END IF;
    END IF;
    RETURN NEW;    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fnc_verter_insert_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW."State" = 'Start' THEN
        IF EXISTS (
                 SELECT "State" FROM Verter WHERE id = NEW.id AND "State" = 'Start'
            ) THEN RAISE EXCEPTION 'Проверка имеет уже статус Start';
        END IF;
    ELSE
        IF NEW."Time" <= (
                SELECT "Time" FROM Verter WHERE NEW."Check" = P2P."Check"
                ORDER BY "Time" DESC LIMIT 1
            )
            THEN RAISE EXCEPTION 'Проверка не может быть завершена раньше, чем она начнется';
        END IF;
        IF NOT EXISTS (	
                SELECT * FROM Verter WHERE "Check" = NEW."Check" AND "State" = 'Start'
		    ) THEN RAISE EXCEPTION 'У проверки нет записи со статусом Start';
		END IF;
    END IF;
    RETURN NEW;    
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER trg_p2p_insert_update
BEFORE INSERT OR UPDATE ON P2P
FOR EACH ROW
EXECUTE FUNCTION fnc_p2p_insert_update();

CREATE TRIGGER trg_verter_insert_update
BEFORE INSERT OR UPDATE ON Verter
FOR EACH ROW
EXECUTE FUNCTION fnc_verter_insert_update();


------------ экспорт в CSV ---------------
CREATE OR REPLACE PROCEDURE prc_export_csv(name_table TEXT, path_file TEXT)
LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE FORMAT('COPY %s TO %L WITH CSV HEADER;', name_table, path_file);
END;
$$;

CALL prc_export_csv('peers', )

------------ импорт из CSV ---------------
CREATE OR REPLACE PROCEDURE prc_import_csv(name_table TEXT, path_file TEXT)
LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE FORMAT('COPY %s FROM %L WITH CSV HEADER;', name_table, path_file);
END;
$$;