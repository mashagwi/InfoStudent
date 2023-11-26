
------- упражнеие 1 --------
CREATE OR REPLACE PROCEDURE pcr_add_p2p_check(checked_peer VARCHAR, checking_peer VARCHAR, task_name VARCHAR, p2p_state check_status, check_time time)
LANGUAGE PLPGSQL AS $$
BEGIN
    IF p2p_state = 'Start' THEN
        INSERT INTO Checks(Peer,Task,Date) VALUES (checked_peer,task_name,CURRENT_DATE);
        INSERT INTO P2P("Check",CheckingPeer,"State","Time") VALUES ((SELECT max(id) FROM Checks),checking_peer,p2p_state,check_time);
    ELSE
        INSERT INTO P2P("Check",CheckingPeer,"State","Time") 
        VALUES ((SELECT max(id) FROM Checks WHERE Peer = checked_peer),checking_peer,p2p_state,check_time);
    END IF;
END; 
$$;

/*
insert into peers values ('braavoss', '1989-06-08');
insert into peers values ('aemmafre', '1999-06-08');
CALL pcr_add_p2p_check('braavoss', 'aemmafre', 'DO1', 'Start', '13:01:52');
SELECT * FROM p2p WHERE CheckingPeer = 'aemmafre';
*/

------- упражнеие 2 --------
CREATE OR REPLACE PROCEDURE pcr_add_verter_check(checked_peer VARCHAR, task_name VARCHAR, verter_state check_status, check_time time)
LANGUAGE PLPGSQL AS $$
BEGIN
    WITH p2p_latest_by_time_succses AS (SELECT "Check" FROM P2P 
    WHERE "State" = 'Success' AND "Check" IS NOT NULL
    ORDER BY "Time" DESC
    LIMIT 1)

    INSERT INTO Verter("Check", "State", "Time")
    SELECT (SELECT "Check" FROM p2p_latest_by_time_succses), verter_state, check_time
    WHERE EXISTS (SELECT 1 FROM p2p_latest_by_time_succses);
END; 
$$;

--CALL pcr_add_verter_check('braavoss','CPP4','Start','13:02:09');

------- упражнеие 3 --------
CREATE OR REPLACE FUNCTION fnc_trg_after_insert_p2p()
RETURNS TRIGGER AS $$
DECLARE peer_value VARCHAR;
BEGIN
    SELECT Peer INTO peer_value FROM Checks
    WHERE Checks.ID = NEW."Check"
    LIMIT 1;
    IF NEW."State" = 'Start' THEN
        UPDATE TransferredPoints SET PointsAmount = PointsAmount + 1
        WHERE TransferredPoints.CheckingPeer = NEW.CheckingPeer
        AND peer_value = TransferredPoints.CheckedPeer;
    ELSE 
		IF NOT EXISTS (
			SELECT *
			FROM TransferredPoints
			WHERE NEW.CheckingPeer = TransferredPoints.CheckingPeer 
			AND peer_value = TransferredPoints.CheckedPeer
		) THEN
		INSERT INTO TransferredPoints(CheckingPeer, CheckedPeer)
		VALUES(NEW.CheckingPeer, (SELECT Peer
							FROM Checks
							WHERE Checks.ID = NEW."Check"
							LIMIT 1));
		END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE TRIGGER trg_after_insert_p2p
AFTER INSERT ON P2P
FOR EACH ROW
EXECUTE FUNCTION fnc_trg_after_insert_p2p();

--INSERT INTO Checks(Peer,Task,Date) VALUES ('lassandra','CPP5',CURRENT_DATE);
--INSERT INTO p2p("Check","checkingpeer","State","Time") VALUES (( SELECT max(id) FROM Checks ), 'aemmafre', 'Success', '01:01:07');

------- упражнеие 4 --------
CREATE OR REPLACE FUNCTION fnc_trg_before_insert_xp()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.XPAmount > (SELECT Tasks.MaxXP 
                    FROM Tasks JOIN Checks ON Tasks.Title = Checks.Task
                    WHERE Checks.id = NEW."Check" LIMIT 1) 
        THEN RAISE EXCEPTION 'Количество XP превышает максимальное количество текущей задачи';
    END IF;
    IF (SELECT COUNT(*)
        FROM P2P JOIN Verter ON P2P."Check" = Verter."Check"
        WHERE P2P."Check" = NEW."Check" AND P2P."State" = 'Success' AND Verter."State" IN ('Success', NULL)) = 0
    THEN RAISE EXCEPTION 'Нельзя добавить XP за неуспешную проверку.';
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE TRIGGER trg_before_insert_xp
AFTER INSERT ON XP
FOR EACH ROW
EXECUTE FUNCTION fnc_trg_before_insert_xp();

INSERT INTO verter("Check","State","Time") VALUES (47, 'Start', '22:01:07');
INSERT INTO verter("Check","State","Time") VALUES (47, 'Success', '23:01:07');
INSERT INTO xp("Check","xpamount") VALUES (51, 250);