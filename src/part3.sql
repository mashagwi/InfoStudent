-- 1 TASK
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

-- 2 TASK

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

-- SELECT * FROM fnc_peers_who_not_out('2023-02-25');

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

-- SELECT * FROM calculate_peer_points_change();

-- 5 TASK
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
CREATE OR REPLACE FUNCTION check_peers_who_finished_block(task_block VARCHAR)
RETURNS TABLE (Peer VARCHAR, "Day" DATE ) AS $$
BEGIN
RETURN QUERY
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
$$ LANGUAGE plpgsql;

-- SELECT * FROM check_peers_who_finished_block('CPP');


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