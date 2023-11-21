-- 1 TASK
DROP FUNCTION IF EXISTS fnc_calc_transferredpoints();

CREATE OR REPLACE FUNCTION fnc_calc_transferredpoints()
RETURNS TABLE (Peer1 varchar, Peer2 varchar, PoinstAmount integer) AS $$
BEGIN
RETURN QUERY (
	SELECT t1.checkingpeer,
	t1.checkedpeer,
	(t1.pointsamount -t2.pointsamount) AS PoinstAmount
	FROM transferredpoints AS t1
	JOIN transferredpoints AS t2 ON
		t1.checkingpeer = t2.checkedpeer
		AND t1.checkedpeer = t2.checkingpeer
		AND t1.id < t2.id);
END;
$$ LANGUAGE plpgsql;

SELECT *
FROM fnc_calc_transferredpoints();

-- 2 TASK NO CORRECT? - should check

DROP FUNCTION IF EXISTS fnc_get_exp_amount();

CREATE OR REPLACE FUNCTION fnc_get_exp_amount()
RETURNS TABLE (Peer VARCHAR, Task VARCHAR, XP INTEGER) AS $$
BEGIN
	RETURN QUERY (
		SELECT checks.peer AS Peer, checks.Task AS Task, xp.xpamount AS XP
		FROM xp
		JOIN checks ON xp."Check" = checks.id);
END;
$$ LANGUAGE plpgsql;

-- 3 TASK

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

SELECT * FROM fnc_peers_who_not_out('2024-01-08');

-- 4 TASK

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

-- 5 TASK

-- 6 TASK
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

-- task 17
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