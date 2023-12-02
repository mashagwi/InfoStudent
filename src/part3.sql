-- 1 TASK --
-- Написать функцию, возвращающую таблицу TransferredPoints в более человекочитаемом виде --
DROP FUNCTION IF EXISTS fnc_tranferred_ponts();

CREATE OR REPLACE FUNCTION fnc_tranferred_ponts()
RETURNS TABLE(Peer1 VARCHAR, Peer2 VARCHAR, "PointsAmount" BIGINT) AS $$
BEGIN
	RETURN QUERY
	WITH reversed AS (
		SELECT
			CASE WHEN CheckingPeer > CheckedPeer THEN CheckingPeer ELSE CheckedPeer END AS CheckingPeer,
			CASE WHEN CheckingPeer > CheckedPeer THEN CheckedPeer ELSE CheckingPeer END AS CheckedPeer,
			CASE WHEN CheckingPeer > CheckedPeer THEN PointsAmount ELSE -PointsAmount END AS PointsAmount
		FROM TransferredPoints
	)
	SELECT CheckingPeer AS peer1, CheckedPeer AS Peer2, SUM(PointsAmount) FROM reversed
	GROUP BY CheckingPeer, CheckedPeer;
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM fnc_tranferred_ponts();

-- 2 TASK --
-- Написать функцию, которая возвращает таблицу вида: ник пользователя, название проверенного задания, кол-во полученного XP --
DROP FUNCTION IF EXISTS fnc_get_exp_amount();

CREATE OR REPLACE FUNCTION fnc_get_exp_amount()
RETURNS TABLE (Peer VARCHAR, Task VARCHAR, XP BIGINT) AS $$
BEGIN
	RETURN QUERY (
		SELECT checks.peer AS Peer, checks.Task AS Task, xp.xpamount AS XP
		FROM xp
		JOIN checks ON xp."Check" = checks.id);
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM fnc_get_exp_amount();

-- 3 TASK --
-- Написать функцию, определяющую пиров, которые не выходили из кампуса в течение всего дня --
DROP FUNCTION IF EXISTS fnc_peers_who_not_out(day_date DATE);

CREATE OR REPLACE FUNCTION fnc_peers_who_not_out(day_date DATE)
RETURNS SETOF VARCHAR AS $$
BEGIN
	RETURN QUERY (
		SELECT peer
		FROM timetracking
		WHERE timetracking."Date" = day_date
		GROUP BY peer, "Date"
		HAVING SUM(CAST(timetracking."State" AS INTEGER)) < 3);
END;
$$ LANGUAGE plpgsql;

-- insert into timetracking("peer","Date","Time","State") values('mashagwi', '2023-03-09', '19:50:52', 1);
-- insert into timetracking("peer","Date","Time","State") values('hildabur', '2023-03-09', '19:50:52', 1);
-- insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-03-09', '19:50:52', 1);

SELECT * FROM fnc_peers_who_not_out('2023-03-09');

-- insert into timetracking("peer","Date","Time","State") values('lassandra', '2023-03-09', '19:58:52', 2);
SELECT * FROM fnc_peers_who_not_out('2023-03-09');

-- 4 TASK --
-- Посчитать изменение в количестве пир поинтов каждого пира по таблице TransferredPoints --
CREATE OR REPLACE FUNCTION calculate_peer_points_change()
RETURNS TABLE (
    Peer VARCHAR,
    PointsChange NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT Changes.checkingpeer AS Peer, SUM(Changes.sum) AS PointsChange
    FROM (
        SELECT CheckingPeer, SUM(PointsAmount)
        FROM TransferredPoints
        GROUP BY CheckingPeer
        UNION ALL
        SELECT CheckedPeer, -SUM(PointsAmount)
        FROM TransferredPoints
        GROUP BY CheckedPeer
    ) AS Changes
    GROUP BY Peer
    ORDER BY PointsChange DESC;

END;
$$ LANGUAGE plpgsql;

SELECT * FROM calculate_peer_points_change();

-- insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('georgier', 'vulpixta', 10);
-- insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('lassandra', 'vulpixta', 10);
-- insert into transferredpoints("checkingpeer","checkedpeer","pointsamount") values ('mashagwi', 'hildabur', 100);
SELECT * FROM calculate_peer_points_change();

-- 5 TASK --
-- Посчитать изменение в количестве пир поинтов каждого пира по таблице, возвращаемой первой функцией из Part 3 --
CREATE OR REPLACE FUNCTION prp_calc_points_transfer_from_func()
RETURNS TABLE(Peer VARCHAR, PointsChange NUMERIC) AS $$
BEGIN
	RETURN QUERY
	WITH sums AS (
		SELECT Peer1 AS Peer, SUM("PointsAmount") AS PointsChange
		FROM fnc_tranferred_ponts()
		GROUP BY Peer1
		UNION 
		SELECT Peer2 AS Peer, -SUM("PointsAmount") AS PointsChange
		FROM fnc_tranferred_ponts()
		GROUP BY Peer2
	)
	SELECT sums.Peer, SUM(sums.PointsChange)
	FROM sums
	GROUP BY sums.Peer
	ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM prp_calc_points_transfer_from_func();

-- 6 TASK --
-- Определить самое часто проверяемое задание за каждый день --
CREATE OR REPLACE FUNCTION get_most_checked_task_per_day()
RETURNS TABLE (
    Date DATE,
    Task VARCHAR
) AS $$
BEGIN
    RETURN QUERY (
        WITH DailyTaskRank AS (
            SELECT
                ch.Date,
                ch.Task,
                RANK() OVER (PARTITION BY ch.Date ORDER BY COUNT(*) DESC) AS task_rank
            FROM Checks ch
            GROUP BY ch.Date, ch.Task
        )
        SELECT
            dtr.Date,
            dtr.Task
        FROM DailyTaskRank dtr
        WHERE task_rank = 1
        ORDER BY Date
    );
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM get_most_checked_task_per_day();

-- 7 TASK
DROP PROCEDURE IF EXISTS check_peers_who_finished_block(rc4 refcursor, branch varchar);

CREATE
OR REPLACE PROCEDURE check_peers_who_finished_block(rc refcursor, task_block varchar) AS
$$
BEGIN
OPEN rc FOR 
WITH list_tasks_of_block AS (
    	SELECT DISTINCT Task
    	FROM Checks
    	WHERE Task LIKE '%' || task_block || '%'
    	ORDER BY 1
	)
	SELECT checks.peer, MAX(date)
	FROM checks 
	JOIN p2p ON p2p."Check" = checks.id
	WHERE 
    	Task LIKE '%' || task_block || '%'
    	AND p2p."State" = 'Success'
	GROUP BY checks.peer
	HAVING COUNT(DISTINCT Task) = (SELECT COUNT(*) FROM list_tasks_of_block)
	ORDER BY 1;
END;
$$
LANGUAGE plpgsql;
-- BEGIN;
-- CALL check_peers_who_finished_block('ref', 'CPP');
-- FETCH ALL IN "ref";
-- END;


-- 8 TASK
CREATE OR REPLACE FUNCTION find_peer_recommendations()
RETURNS TABLE (
    Peer VARCHAR,
    RecommendedPeer TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.Nickname AS Peer,
        MAX(r.RecommendedPeer) AS RecommendedPeer
    FROM
        Peers p
    JOIN Recommendations r ON p.Nickname = r.Peer
    GROUP BY
        p.Nickname;
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM find_peer_recommendations();

-- 9 TASK
DROP PROCEDURE IF EXISTS BlocksStart CASCADE;
CREATE OR REPLACE PROCEDURE BlocksStart(IN p_block1 text, IN p_block2 text, IN r refcursor) AS $$
BEGIN
    OPEN r FOR
    WITH PeerBlocks AS (
        SELECT DISTINCT p.Nickname, 
                        CASE 
                            WHEN EXISTS (SELECT 1 FROM Checks c WHERE c.Peer = p.Nickname AND c.Task LIKE CONCAT('%', p_block1, '%')) THEN 1
                            ELSE 0
                        END AS Block1,
                        CASE 
                            WHEN EXISTS (SELECT 1 FROM Checks c WHERE c.Peer = p.Nickname AND c.Task LIKE CONCAT('%', p_block2, '%')) THEN 1
                            ELSE 0
                        END AS Block2
        FROM Peers p
    )
    SELECT 
        ROUND((COUNT(Nickname) FILTER (WHERE Block1 = 1 AND Block2 = 0) * 100 / COUNT(Nickname)))::integer AS "StartedBlock1",
        ROUND((COUNT(Nickname) FILTER (WHERE Block1 = 0 AND Block2 = 1) * 100 / COUNT(Nickname)))::integer AS "StartedBlock2",
        ROUND((COUNT(Nickname) FILTER (WHERE Block1 = 1 AND Block2 = 1) * 100 / COUNT(Nickname)))::integer AS "StartedBothBlock",
        ROUND((COUNT(Nickname) FILTER (WHERE Block1 = 0 AND Block2 = 0) * 100 / COUNT(Nickname)))::integer AS "DidntStartedAnyBlock"
    FROM PeerBlocks;
END;
$$
LANGUAGE plpgsql;
-- BEGIN;
-- CALL BlocksStart('C', 'DO', 'ref');
-- FETCH ALL IN "ref";
-- END;


-- 10 TASK
CREATE OR REPLACE PROCEDURE checks_in_birthday(INOUT _result_one refcursor = 'rs')
    LANGUAGE plpgsql AS
$$
BEGIN
OPEN _result_one FOR 
WITH peers_birthdays AS (
	SELECT nickname, TO_CHAR(birthday, 'MM-DD') AS birthday
	FROM peers
), peers_failures AS (
	SELECT c.peer, TO_CHAR(c.date, 'MM-DD') AS check_date, 'Failure' AS "State"
	FROM Checks c
	WHERE c.ID IN (
    	SELECT DISTINCT c.ID
    	FROM Checks c
    	LEFT JOIN Verter v ON c.ID = v."Check" AND v."State" = 'Failure'
    	LEFT JOIN P2P p ON c.ID = p."Check" AND p."State" = 'Failure'
    	WHERE v.ID IS NOT NULL OR p.ID IS NOT NULL
	)
), peers_success AS (
	SELECT c.peer, TO_CHAR(c.date, 'MM-DD') AS check_date, 'Success' AS "State"
    FROM Checks c
    WHERE c.ID IN (
        SELECT DISTINCT c.ID
        FROM Checks c
        LEFT JOIN Verter v ON c.ID = v."Check" AND v."State" = 'Success'
        JOIN P2P p ON c.ID = p."Check" AND p."State" = 'Success'
        WHERE (v.ID IS NOT NULL OR p.ID IS NOT NULL)
    )
), all_checks_in_birthday AS (
	SELECT pb.nickname, pb.birthday, ps."State"
	FROM peers_birthdays pb
	JOIN peers_success ps ON pb.nickname = ps.peer AND pb.birthday = ps.check_date
	UNION ALL
	SELECT pb.nickname, pb.birthday, pf."State"
	FROM peers_birthdays pb
	JOIN peers_failures pf ON pb.nickname = pf.peer AND pb.birthday = pf.check_date
)
SELECT
    ROUND(COUNT(*) FILTER (WHERE "State" = 'Success') * 100.0 / COUNT(*)) AS SuccessfulChecks,
    ROUND(COUNT(*) FILTER (WHERE "State" = 'Failure') * 100.0 / COUNT(*)) AS unSuccessfulChecks
FROM all_checks_in_birthday;
END
$$;
-- BEGIN;
-- CALL checks_in_birthday();
-- FETCH ALL FROM "rs";
-- END;


-- 11 TASK
DROP PROCEDURE IF EXISTS pass CASCADE;
CREATE
OR REPLACE PROCEDURE pass(IN task1 varchar, IN task2 varchar, IN task3 varchar, IN r refcursor) AS $$
BEGIN
OPEN r FOR
    WITH SuccessTasks AS (
	SELECT peer,
	task
	FROM checks
	JOIN p2p ON checks.id = p2p."Check"
	LEFT JOIN verter ON checks.id = verter."Check"
	WHERE p2p."State" = 'Success'
	AND (NOT exists(SELECT * FROM verter WHERE verter."Check" = checks.id)
		 OR
		 verter."State" = 'Success')
)
SELECT DISTINCT peer as nickname
FROM SuccessTasks
WHERE peer in (SELECT peer FROM SuccessTasks WHERE task = task1)
  AND peer in (SELECT peer FROM SuccessTasks WHERE task = task2)
  AND peer NOT IN (SELECT peer FROM SuccessTasks WHERE task = task3);
END;
    $$LANGUAGE
plpgsql;
-- BEGIN;
-- CALL pass('DO1', 'DO2' , 'A8', 'r');
-- FETCH ALL IN "r";
-- END;

-- 12 TASK
CREATE OR REPLACE FUNCTION get_preceding_tasks()
RETURNS TABLE (
    Task VARCHAR,
    PrevCount INT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE cte_tasks_count AS (
        SELECT
            title,
            0 AS count,
            parenttask
        FROM tasks
        WHERE parenttask IS NULL
        UNION ALL
        SELECT
            t.title,
            count + 1,
            t.parenttask
        FROM tasks AS t
        JOIN cte_tasks_count AS cte_tc ON cte_tc.title = t.parenttask
    )
    SELECT title AS Task, count AS PrevCount
    FROM cte_tasks_count
    ORDER BY Task;
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM get_preceding_tasks()

-- 13 TASK
CREATE
OR REPLACE PROCEDURE successful_day(rc refcursor, succesful_streak integer) AS
$$
BEGIN
OPEN rc FOR WITH temp AS (SELECT *
                                 FROM checks
                                          JOIN p2p p
                                          ON checks.id = p."Check"
                                          LEFT JOIN verter v
                                          ON checks.id = v."Check"
                                          JOIN tasks t
                                          ON t.title = checks.task
                                          JOIN xp x
                                          ON checks.id = x."Check"
                                WHERE p."State" = 'Success'
                                  AND (v."State" = 'Success' OR v."State" IS NULL))
SELECT date
FROM temp
WHERE temp.maxxp * 0.8 <= temp.xpamount
GROUP BY temp.date
HAVING COUNT(date) >= succesful_streak
ORDER BY date;
END;
$$
LANGUAGE plpgsql;
-- BEGIN;
-- CALL successful_day('ref', 2);
-- FETCH ALL IN "ref";
-- END;

-- 14 TASK
CREATE OR REPLACE FUNCTION find_peer_with_highest_xp()
RETURNS TABLE (
    Peer VARCHAR,
    TotalXP NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT P2P.checkingpeer AS Peer, SUM(xp.XPAmount) AS TotalXP
    FROM P2P
    JOIN Checks ON P2P."Check" = Checks.ID AND P2P."State" = 'Success'
    JOIN XP xp ON Checks.ID = xp."Check"
    GROUP BY P2P.checkingpeer
    ORDER BY TotalXP DESC
    LIMIT 1;

END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM find_peer_with_highest_xp();

-- 15 TASK 
DROP PROCEDURE IF EXISTS PeersInCampusEarlyEntries;
CREATE OR REPLACE PROCEDURE PeersInCampusEarlyEntries(IN determinated_time time, IN N int, IN r refcursor) AS $$
BEGIN
OPEN r FOR
SELECT t.peer 
		FROM TimeTracking AS t
		WHERE t."Time" < determinated_time
		GROUP BY t.peer
		HAVING COUNT(*) >= N;
END;
    $$LANGUAGE
plpgsql;
-- BEGIN;
-- CALL PeersInCampusEarlyEntries('12:00:00', 3, 'ref');
-- FETCH ALL IN "ref";
-- END;

-- 16 TASK
DROP PROCEDURE IF EXISTS PeersOutCampus CASCADE;
CREATE
OR REPLACE PROCEDURE PeersOutCampus(IN N int, IN M int, IN r refcursor) AS $$
BEGIN
OPEN r FOR
	SELECT peer
	FROM timetracking
	WHERE "Date" >= current_date - N AND "State" = '2'
	GROUP BY peer, "Date"
	HAVING COUNT("State") > M;
END;
$$LANGUAGE plpgsql;
-- BEGIN;
-- CALL PeersOutCampus(9, 1, 'r');
-- FETCH ALL IN "r";
-- END;

-- 17 TASK
CREATE OR REPLACE FUNCTION calculate_early_entries_percentage()
RETURNS TABLE (
    Month text,
    EarlyEntriesPercentage INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        TO_CHAR("Date", 'Month') AS Month,
        ROUND((COUNT(*) FILTER (WHERE EXTRACT(HOUR FROM "Time") < 12)::NUMERIC / COUNT(*)) * 100)::INTEGER AS EarlyEntriesPercentage
    FROM TimeTracking
    WHERE EXTRACT(MONTH FROM "Date") IS NOT NULL
    GROUP BY TO_CHAR("Date", 'Month')
    ORDER BY TO_CHAR("Date", 'Month');
END;
$$ LANGUAGE plpgsql;
-- SELECT * FROM calculate_early_entries_percentage();