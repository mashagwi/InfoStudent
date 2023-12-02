--CREATE DATABASE S21_Info;

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

CREATE OR REPLACE FUNCTION fnc_trg_tasks_before_insert_update()
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

CREATE TRIGGER trg_tasks_before_insert_update
BEFORE INSERT OR UPDATE ON Tasks
FOR EACH ROW
EXECUTE FUNCTION fnc_trg_tasks_before_insert_update();

CREATE OR REPLACE FUNCTION fnc_p2p_before_insert_update()
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

CREATE TRIGGER trg_p2p_before_insert_update
BEFORE INSERT OR UPDATE ON P2P
FOR EACH ROW
EXECUTE FUNCTION fnc_p2p_before_insert_update();

CREATE OR REPLACE FUNCTION fnc_verter_before_insert_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW."State" = 'Start' THEN
        IF EXISTS (
                 SELECT "State" FROM Verter WHERE id = NEW.id AND "State" = 'Start'
            ) THEN RAISE EXCEPTION 'Проверка имеет уже статус Start';
        END IF;
    ELSE
        IF NEW."Time" <= (
                SELECT "Time" FROM Verter WHERE NEW."Check" = Verter."Check"
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

CREATE TRIGGER trg_verter_before_insert_update
BEFORE INSERT OR UPDATE ON Verter
FOR EACH ROW
EXECUTE FUNCTION fnc_verter_before_insert_update();


------------ экспорт в CSV ---------------
CREATE OR REPLACE PROCEDURE prc_export_csv(name_table TEXT, path_file TEXT)
LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE FORMAT('COPY %s TO %L WITH CSV HEADER;', name_table, path_file);
END;
$$;

--CALL prc_export_csv('peers', '/tmp/peers.csv');
--TRUNCATE peers CASCADE;

------------ импорт из CSV ---------------
CREATE OR REPLACE PROCEDURE prc_import_csv(name_table TEXT, path_file TEXT)
LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE FORMAT('COPY %s FROM %L WITH CSV HEADER;', name_table, path_file);
END;
$$;

--CALL prc_import_csv('peers', '/tmp/peers.csv');

insert into peers values('norridge', '1989-04-02');
insert into peers values('georgier', '1999-02-05');
insert into peers values('hildabur', '1999-10-15');
insert into peers values('vulpixta', '2001-12-26');
insert into peers values('mashagwi', '2000-12-24');
insert into peers values('lassandra', '1990-02-12');
insert into peers values('mavissig', '1995-05-08');

insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values('hildabur', 'mavissig', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'hildabur', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'vulpixta', 4);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'hildabur', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'lassandra', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'vulpixta', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'norridge', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'norridge', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'mashagwi', 4);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'georgier', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'georgier', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'mavissig', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'norridge', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'hildabur', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'vulpixta', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'hildabur', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'norridge', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'norridge', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'hildabur', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'vulpixta', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'mavissig', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'hildabur', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'vulpixta', 4);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'hildabur', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'lassandra', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'vulpixta', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'norridge', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'norridge', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'mashagwi', 4);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('hildabur', 'georgier', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'georgier', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'mavissig', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'mavissig', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'norridge', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'hildabur', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'vulpixta', 3);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'hildabur', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'norridge', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('norridge', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('vulpixta', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'norridge', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'hildabur', 2);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'mashagwi', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mavissig', 'lassandra', 1);
insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'vulpixta', 1);


insert into tasks values('DO1', null, 300);
insert into tasks values('DO2', 'DO1', 250);
insert into tasks values('DO3', 'DO2', 350);
insert into tasks values('DO4', 'DO3', 350);
insert into tasks values('DO5', 'DO4', 300);
insert into tasks values('DO6', 'DO5', 300);

insert into tasks values('CPP1', 'DO6', 300);
insert into tasks values('CPP2', 'CPP1', 400);
insert into tasks values('CPP3', 'CPP2', 300);
insert into tasks values('CPP4', 'CPP3', 350);
insert into tasks values('CPP5', 'CPP4', 400);

insert into tasks values('A1', 'CPP5', 300);
insert into tasks values('A2', 'A1', 400);
insert into tasks values('A3', 'A2', 300);
insert into tasks values('A4', 'A3', 350);
insert into tasks values('A5', 'A4', 400);
insert into tasks values('A6', 'A5', 700);
insert into tasks values('A7', 'A6', 800);
insert into tasks values('A8', 'A7', 800);

insert into tasks values('SQL1', 'A8', 1500);
insert into tasks values('SQL2', 'SQL1', 500);
insert into tasks values('SQL3', 'SQL2', 600);


insert into checks("peer","task","date") values('hildabur', 'DO1', '2023-12-01');
insert into checks("peer","task","date") values('mashagwi', 'A1', '2023-12-01');
insert into checks("peer","task","date") values('lassandra', 'A1', '2023-12-01');
insert into checks("peer","task","date") values('lassandra', 'A2', '2023-12-03');
insert into checks("peer","task","date") values('hildabur', 'DO2', '2023-12-10');
insert into checks("peer","task","date") values('mashagwi', 'A2', '2023-12-10');
insert into checks("peer","task","date") values('lassandra', 'A3', '2023-12-10');

insert into checks("peer","task","date") values('hildabur', 'DO3', '2023-12-15');
insert into checks("peer","task","date") values('mashagwi', 'A3', '2023-12-15');
insert into checks("peer","task","date") values('lassandra', 'A4', '2023-12-15');

insert into checks("peer","task","date") values('hildabur', 'DO4', '2023-12-24');
insert into checks("peer","task","date") values('mashagwi', 'A4', '2023-12-24');
insert into checks("peer","task","date") values('lassandra', 'A5', '2023-12-24');

insert into checks("peer","task","date") values('hildabur', 'DO5', '2023-01-03');
insert into checks("peer","task","date") values('georgier', 'DO1', '2023-01-03');
insert into checks("peer","task","date") values('mashagwi', 'A5', '2023-01-03');

insert into checks("peer","task","date") values('georgier', 'DO1', '2023-01-05');

insert into checks("peer","task","date") values('georgier', 'DO2', '2023-01-15');
insert into checks("peer","task","date") values('hildabur', 'DO6', '2023-01-15');
insert into checks("peer","task","date") values('mashagwi', 'A6', '2023-01-15');
insert into checks("peer","task","date") values('lassandra', 'A6', '2023-01-15');

insert into checks("peer","task","date") values('hildabur', 'CPP1', '2023-02-01');
insert into checks("peer","task","date") values('georgier', 'CPP1', '2023-02-01');
insert into checks("peer","task","date") values('mashagwi', 'A7', '2023-02-01');
insert into checks("peer","task","date") values('lassandra', 'A7', '2023-02-01');

insert into checks("peer","task","date") values('vulpixta', 'CPP1', '2023-02-04');
insert into checks("peer","task","date") values('norridge', 'CPP1', '2023-02-04');

insert into checks("peer","task","date") values('georgier', 'CPP2', '2023-02-05');
insert into checks("peer","task","date") values('vulpixta', 'CPP2', '2023-02-05');
insert into checks("peer","task","date") values('norridge', 'CPP2', '2023-02-05');

insert into checks("peer","task","date") values('georgier', 'CPP2', '2023-02-09');
insert into checks("peer","task","date") values('vulpixta', 'CPP3', '2023-02-09');
insert into checks("peer","task","date") values('norridge', 'CPP3', '2023-02-09');

insert into checks("peer","task","date") values('georgier', 'CPP3', '2023-02-12');
insert into checks("peer","task","date") values('mashagwi', 'A8', '2023-02-12');
insert into checks("peer","task","date") values('vulpixta', 'CPP4', '2023-02-12');
insert into checks("peer","task","date") values('lassandra', 'A8', '2023-02-12');
insert into checks("peer","task","date") values('norridge', 'CPP4', '2023-02-12');

insert into checks("peer","task","date") values('norridge', 'CPP5', '2023-02-25');

insert into checks("peer","task","date") values('mashagwi', 'SQL1', '2023-02-27');
insert into checks("peer","task","date") values('lassandra', 'A8', '2023-02-27');
insert into checks("peer","task","date") values('vulpixta', 'CPP5', '2023-02-27');
insert into checks("peer","task","date") values('mavissig', 'SQL1', '2023-02-27');
insert into checks("peer","task","date") values('lassandra', 'SQL1', '2023-02-27');
insert into checks("peer","task","date") values('norridge', 'CPP5', '2023-02-27');

insert into checks("peer","task","date") values('lassandra', 'SQL2', '2023-03-01');
insert into checks("peer","task","date") values('mavissig', 'SQL2', '2023-03-01');

insert into checks("peer","task","date") values('mavissig', 'SQL3', '2023-03-05');

insert into checks("peer","task","date") values('mavissig', 'SQL3', '2023-03-06');

insert into checks("peer","task","date") values('mavissig', 'SQL3', '2023-03-07');
insert into checks("peer","task","date") values('georgier', 'DO2', '2023-03-07');
insert into checks("peer","task","date") values('hildabur', 'SQL1', '2023-03-07');
insert into checks("peer","task","date") values('norridge', 'CPP5', '2023-03-07');

insert into checks("peer","task","date") values('georgier', 'DO1', '2023-03-08');


insert into p2p("Check","checkingpeer","State","Time") values(1, 'mavissig', 'Start', '16:00:57');
insert into p2p("Check","checkingpeer","State","Time") values(1, 'mavissig', 'Success', '17:00:25');

insert into p2p("Check","checkingpeer","State","Time") values(2, 'mavissig', 'Start', '16:18:57');
insert into p2p("Check","checkingpeer","State","Time") values(2, 'mavissig', 'Success', '17:00:25');

insert into p2p("Check","checkingpeer","State","Time") values(3, 'hildabur', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(3, 'hildabur', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(4, 'vulpixta', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(4, 'vulpixta', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(5, 'lassandra', 'Start', '15:16:17');
insert into p2p("Check","checkingpeer","State","Time") values(5, 'lassandra', 'Success', '16:17:18');

insert into p2p("Check","checkingpeer","State","Time") values(6, 'hildabur', 'Start', '18:15:20');
insert into p2p("Check","checkingpeer","State","Time") values(6, 'hildabur', 'Success', '19:15:21');

insert into p2p("Check","checkingpeer","State","Time") values(7, 'mavissig', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(7, 'mavissig', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(8, 'mashagwi', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(8, 'mashagwi', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(9, 'lassandra', 'Start', '10:19:20');
insert into p2p("Check","checkingpeer","State","Time") values(9, 'lassandra', 'Success', '11:20:21');

insert into p2p("Check","checkingpeer","State","Time") values(10, 'vulpixta', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(10, 'vulpixta', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(11, 'vulpixta', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(11, 'vulpixta', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(12, 'norridge', 'Start', '18:19:20');
insert into p2p("Check","checkingpeer","State","Time") values(12, 'norridge', 'Success', '19:20:21');

insert into p2p("Check","checkingpeer","State","Time") values(13, 'norridge', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(13, 'norridge', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(14, 'mavissig', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(14, 'mavissig', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(15, 'mavissig', 'Start', '12:13:14');
insert into p2p("Check","checkingpeer","State","Time") values(15, 'mavissig', 'Failure', '13:14:15');

insert into p2p("Check","checkingpeer","State","Time") values(16, 'norridge', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(16, 'norridge', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(17, 'mashagwi', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(17, 'mashagwi', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(18, 'mashagwi', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(18, 'mashagwi', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(19, 'georgier', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(19, 'georgier', 'Success', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(20, 'georgier', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(20, 'georgier', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(21, 'vulpixta', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(21, 'vulpixta', 'Success', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(22, 'mavissig', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(22, 'mavissig', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(23, 'mashagwi', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(23, 'mashagwi', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(24, 'lassandra', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(24, 'lassandra', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(25, 'norridge', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(25, 'norridge', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(26, 'mavissig', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(26, 'mavissig', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(27, 'mavissig', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(27, 'mavissig', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(28, 'norridge', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(28, 'norridge', 'Success', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(29, 'hildabur', 'Start', '17:18:19');
insert into p2p("Check","checkingpeer","State","Time") values(29, 'hildabur', 'Success', '18:19:20');

insert into p2p("Check","checkingpeer","State","Time") values(30, 'vulpixta', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(30, 'vulpixta', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(31, 'hildabur', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(31, 'hildabur', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(32, 'norridge', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(32, 'norridge', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(33, 'mashagwi', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(33, 'mashagwi', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(34, 'mashagwi', 'Start', '16:00:57');

insert into p2p("Check","checkingpeer","State","Time") values(35, 'lassandra', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(35, 'lassandra', 'Success', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(36, 'hildabur', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(36, 'hildabur', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(37, 'hildabur', 'Start', '16:00:57');
insert into p2p("Check","checkingpeer","State","Time") values(37, 'hildabur', 'Failure', '17:00:25');

insert into p2p("Check","checkingpeer","State","Time") values(38, 'mavissig', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(38, 'mavissig', 'Success', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(39, 'vulpixta', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(39, 'vulpixta', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(40, 'norridge', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(40, 'norridge', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(41, 'norridge', 'Start', '20:21:22');
insert into p2p("Check","checkingpeer","State","Time") values(41, 'norridge', 'Success', '21:22:23');

insert into p2p("Check","checkingpeer","State","Time") values(42, 'lassandra', 'Start', '15:00:40');

insert into p2p("Check","checkingpeer","State","Time") values(43, 'norridge', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(43, 'norridge', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(44, 'vulpixta', 'Start', '19:30:21');
insert into p2p("Check","checkingpeer","State","Time") values(44, 'vulpixta', 'Success', '20:00:00');

insert into p2p("Check","checkingpeer","State","Time") values(45, 'vulpixta', 'Start', '16:00:57');
insert into p2p("Check","checkingpeer","State","Time") values(45, 'vulpixta', 'Success', '17:00:25');

insert into p2p("Check","checkingpeer","State","Time") values(46, 'hildabur', 'Start', '08:01:21');
insert into p2p("Check","checkingpeer","State","Time") values(46, 'hildabur', 'Success', '08:30:02');

insert into p2p("Check","checkingpeer","State","Time") values(47, 'hildabur', 'Start', '15:00:40');
insert into p2p("Check","checkingpeer","State","Time") values(47, 'hildabur', 'Success', '15:26:22');

insert into p2p("Check","checkingpeer","State","Time") values(48, 'hildabur', 'Start', '20:15:21');
insert into p2p("Check","checkingpeer","State","Time") values(48, 'hildabur', 'Failure', '21:10:05');

insert into p2p("Check","checkingpeer","State","Time") values(49, 'mashagwi', 'Start', '21:22:23');
insert into p2p("Check","checkingpeer","State","Time") values(49, 'mashagwi', 'Failure', '22:23:24');

insert into p2p("Check","checkingpeer","State","Time") values(50, 'lassandra', 'Start', '14:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(50, 'lassandra', 'Success', '15:07:55');

insert into p2p("Check","checkingpeer","State","Time") values(51, 'vulpixta', 'Start', '21:16:07');
insert into p2p("Check","checkingpeer","State","Time") values(51, 'vulpixta', 'Success', '21:40:55');

insert into p2p("Check","checkingpeer","State","Time") values(52, 'vulpixta', 'Start', '23:00:05');
insert into p2p("Check","checkingpeer","State","Time") values(52, 'vulpixta', 'Success', '23:30:55');

insert into p2p("Check","checkingpeer","State","Time") values(53, 'mavissig', 'Start', '22:00:05');
insert into p2p("Check","checkingpeer","State","Time") values(53, 'mavissig', 'Success', '22:30:55');

insert into p2p("Check","checkingpeer","State","Time") values(54, 'mashagwi', 'Start', '20:00:05');
insert into p2p("Check","checkingpeer","State","Time") values(54, 'mashagwi', 'Success', '21:30:55');


insert into timetracking("peer","Date","Time","State") values('norridge', '2023-11-01', '11:24:11', 1);
insert into timetracking("peer","Date","Time","State") values('norridge', '2023-11-01', '23:42:00', 2);

insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-11-01', '09:05:54', 1);
insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-11-01', '23:42:00', 2);

insert into timetracking("peer","Date","Time","State") values('georgier', '2023-11-05', '13:44:01', 1);
insert into timetracking("peer","Date","Time","State") values('georgier', '2023-11-05', '23:42:00', 2);

insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-11-07', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-11-07', '23:59:59', 2);

insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-11-10', '23:59:59', 1);
insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-11-11', '02:42:59', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-11-11', '05:41:34', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-11-11', '20:30:47', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-11-24', '10:14:22', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-11-24', '12:29:17', 2);

insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-11-28', '20:30:47', 1);
insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-11-29', '00:49:44', 2);

insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-11-30', '13:49:44', 1);
insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-11-30', '21:17:02', 2);

insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-11-30', '19:07:45', 1);
insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-11-30', '21:17:55', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-01-01', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-01-01', '23:59:59', 2);

insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-01-01', '10:10:00', 1);
insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-01-01', '22:05:59', 2);

insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-01-01', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-01-01', '00:59:59', 2);

insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-01-10', '08:50:52', 1);
insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-01-10', '17:04:02', 2);

insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-01-20', '15:59:59', 1);
insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-01-20', '23:59:52', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-01-30', '09:41:34', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-01-30', '20:00:47', 2);

insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-02-04', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-02-05', '00:50:44', 2);

insert into timetracking("peer","Date","Time","State") values('norridge', '2023-02-04', '03:15:54', 1);
insert into timetracking("peer","Date","Time","State") values('norridge', '2023-02-04', '11:24:14', 2);

insert into timetracking("peer","Date","Time","State") values('georgier', '2023-02-05', '11:01:45', 1);
insert into timetracking("peer","Date","Time","State") values('georgier', '2023-02-05', '19:14:34', 2);

insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-02-12', '21:14:05', 1);
insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-02-13', '00:07:42', 2);

insert into timetracking("peer","Date","Time","State") values('georgier', '2023-02-16', '13:49:44', 1);
insert into timetracking("peer","Date","Time","State") values('georgier', '2023-02-17', '05:17:02', 2);

insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-02-25', '19:07:45', 1);
insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-02-25', '22:14:04', 2);

insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-02-27', '10:08:21', 1);
insert into timetracking("peer","Date","Time","State") values('vulpixta', '2023-02-27', '20:05:17', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-03-07', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-03-08', '09:04:16', 2);

insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-03-07', '01:14:00', 1);
insert into timetracking("peer","Date","Time","State") values('mavissig', '2023-03-07', '17:04:02', 2);

insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-03-08', '19:50:52', 1);
insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-03-08', '21:04:02', 2);

/*
insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-01', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-01', '23:59:58', 2);

insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-02', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-02', '23:59:59', 2);

insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-03', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('username1', '2024-01-04', '00:00:00', 2);

insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-05', '12:53:21', 1);
insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-05', '21:01:31', 2);

insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-06', '13:22:13', 1);
insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-06', '16:21:53', 2);

insert into timetracking("peer","Date","Time","State") values('username3', '2024-01-07', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('username3', '2024-01-07', '23:59:59', 2);

insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-08', '00:00:00', 1);
insert into timetracking("peer","Date","Time","State") values('username2', '2024-01-08', '23:59:59', 2);
insert into timetracking("peer","Date","Time","State") values('username3', '2024-01-08', '00:00:00', 1);
*/

insert into friends("peer1","peer2") values('norridge', 'georgier');
insert into friends("peer1","peer2") values('norridge', 'mavissig');
insert into friends("peer1","peer2") values('norridge', 'lassandra');
insert into friends("peer1","peer2") values('georgier', 'hildabur');
insert into friends("peer1","peer2") values('georgier', 'mavissig');
insert into friends("peer1","peer2") values('hildabur', 'lassandra');
insert into friends("peer1","peer2") values('hildabur', 'vulpixta');
insert into friends("peer1","peer2") values('vulpixta', 'norridge');
insert into friends("peer1","peer2") values('vulpixta', 'mashagwi');
insert into friends("peer1","peer2") values('mashagwi', 'norridge');
insert into friends("peer1","peer2") values('mavissig', 'hildabur');
insert into friends("peer1","peer2") values('lassandra', 'mavissig');

insert into recommendations("peer", "recommendedpeer") values('norridge', 'hildabur');
insert into recommendations("peer", "recommendedpeer") values('norridge', 'vulpixta');
insert into recommendations("peer", "recommendedpeer") values('norridge', 'mashagwi');
insert into recommendations("peer", "recommendedpeer") values('georgier', 'vulpixta');
insert into recommendations("peer", "recommendedpeer") values('hildabur', 'mavissig');
insert into recommendations("peer", "recommendedpeer") values('hildabur', 'lassandra');
insert into recommendations("peer", "recommendedpeer") values('vulpixta', 'georgier');
insert into recommendations("peer", "recommendedpeer") values('vulpixta', 'lassandra');
insert into recommendations("peer", "recommendedpeer") values('mashagwi', 'lassandra');
insert into recommendations("peer", "recommendedpeer") values('mashagwi', 'norridge');
insert into recommendations("peer", "recommendedpeer") values('mashagwi', 'vulpixta');
insert into recommendations("peer", "recommendedpeer") values('mashagwi', 'mavissig');
insert into recommendations("peer", "recommendedpeer") values('lassandra', 'georgier');
insert into recommendations("peer", "recommendedpeer") values('mavissig', 'georgier');
insert into recommendations("peer", "recommendedpeer") values('mavissig', 'vulpixta');
insert into recommendations("peer", "recommendedpeer") values('mavissig', 'lassandra');


insert into xp("Check","xpamount") values(1, 300);
insert into xp("Check","xpamount") values(2, 300);
insert into xp("Check","xpamount") values(3, 300);
insert into xp("Check","xpamount") values(4, 400);
insert into xp("Check","xpamount") values(5, 240);
insert into xp("Check","xpamount") values(6, 400);
insert into xp("Check","xpamount") values(7, 300);
insert into xp("Check","xpamount") values(8, 350);
insert into xp("Check","xpamount") values(9, 300);
insert into xp("Check","xpamount") values(10, 350);
insert into xp("Check","xpamount") values(11, 350);
insert into xp("Check","xpamount") values(12, 350);
insert into xp("Check","xpamount") values(13, 400);
insert into xp("Check","xpamount") values(14, 300);
insert into xp("Check","xpamount") values(16, 400);
insert into xp("Check","xpamount") values(17, 290);
insert into xp("Check","xpamount") values(18, 240);
insert into xp("Check","xpamount") values(19, 300);
insert into xp("Check","xpamount") values(20, 700);
insert into xp("Check","xpamount") values(21, 700);
insert into xp("Check","xpamount") values(22, 300);
insert into xp("Check","xpamount") values(23, 300);
insert into xp("Check","xpamount") values(24, 800);
insert into xp("Check","xpamount") values(25, 800);
insert into xp("Check","xpamount") values(26, 300);
insert into xp("Check","xpamount") values(27, 300);
insert into xp("Check","xpamount") values(29, 400);
insert into xp("Check","xpamount") values(30, 400);
insert into xp("Check","xpamount") values(31, 300);
insert into xp("Check","xpamount") values(32, 300);
insert into xp("Check","xpamount") values(33, 300);
insert into xp("Check","xpamount") values(35, 800);
insert into xp("Check","xpamount") values(36, 340);
insert into xp("Check","xpamount") values(38, 350);
insert into xp("Check","xpamount") values(40, 1500);
insert into xp("Check","xpamount") values(41, 800);
insert into xp("Check","xpamount") values(43, 1400);
insert into xp("Check","xpamount") values(44, 1500);
insert into xp("Check","xpamount") values(45, 390);
insert into xp("Check","xpamount") values(46, 500);
insert into xp("Check","xpamount") values(47, 500);
insert into xp("Check","xpamount") values(50, 580);
insert into xp("Check","xpamount") values(51, 250);
insert into xp("Check","xpamount") values(52, 1450);
insert into xp("Check","xpamount") values(53, 400);
insert into xp("Check","xpamount") values(54, 300);


insert into verter values (1, 1,'Start', '11:02:03');
insert into verter values (2, 1,'Success', '11:02:08');

insert into verter values (3, 2,'Start', '11:03:03');
insert into verter values (4, 2,'Success', '11:03:08');

insert into verter values (5, 3,'Start', '11:05:03');
insert into verter values (6, 3,'Success', '11:05:08');

insert into verter values (7, 4,'Start', '11:06:03');
insert into verter values (8, 4,'Success', '11:06:08');