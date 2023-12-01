-- Создание базы данных
CREATE DATABASE database_test;

-- Создание таблиц
CREATE TABLE TableName1 (id serial PRIMARY KEY, name VARCHAR(255));
CREATE TABLE TableName2 (id serial PRIMARY KEY, description VARCHAR(255));
CREATE TABLE OtherTable (id serial PRIMARY KEY, description VARCHAR(255));

-- 1) Создать хранимую процедуру, которая, не уничтожая базу данных,
-- уничтожает все те таблицы текущей базы данных, имена которых начинаются с фразы 'TableName'.

CREATE OR REPLACE PROCEDURE drop_tables_with_prefix(prefix_to_drop TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    cur_table_name TEXT;
    drop_query TEXT;
BEGIN
    -- Получаем список таблиц в текущей базе данных
    FOR cur_table_name IN (SELECT table_name FROM information_schema.tables 
                            WHERE table_schema = 'public' AND table_name LIKE prefix_to_drop || '%') 
    LOOP
        -- Формируем запрос для удаления таблицы
        drop_query := 'DROP TABLE IF EXISTS ' || cur_table_name || ' CASCADE';
        EXECUTE drop_query;
    END LOOP;
END;
$$;

--Тестовый вызов процедуры
CALL drop_tables_with_prefix('tablename');

--Выводим список таблиц в БД
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public';

DROP PROCEDURE IF EXISTS drop_tables_with_prefix CASCADE;

-- 2) Создать хранимую процедуру с выходным параметром, которая выводит список имен и параметров   
--всех скалярных SQL функций пользователя в текущей базе данных. Имена функций без параметров не выводить. 
--Имена и список параметров должны выводиться в одну строку. 
--Выходной параметр возвращает количество найденных функций.

CREATE OR REPLACE PROCEDURE get_scalar_functions_info(
    OUT num_functions INT,
    OUT function_info TEXT[]
) AS
$$
DECLARE
    function_name   TEXT;
    function_params TEXT;
    cur             refcursor;
BEGIN
    num_functions := 0;
    function_info := ARRAY[]::TEXT[];

    OPEN cur FOR
    SELECT p.proname, pg_get_function_identity_arguments(p.oid)
    FROM pg_proc p
           JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND NOT EXISTS (
        SELECT 1
        FROM pg_aggregate a
        WHERE a.aggfnoid = p.oid
      )
      AND pg_get_function_result(p.oid)::regtype <> 'trigger'::regtype -- исключаем триггерные функции
      AND pg_get_function_result(p.oid)::regtype <> 'internal'::regtype -- исключаем внутренние функции
      AND p.proretset = 'f' -- только скалярные функции (не возвращающие набор)
      AND p.pronargs > 0 -- с параметрами
    ORDER BY p.proname;

    LOOP
        FETCH cur INTO function_name, function_params;

        EXIT WHEN NOT FOUND;

        num_functions := num_functions + 1;
        function_info := function_info || ARRAY[function_name || '(' || function_params || ')'];
    END LOOP;

    CLOSE cur;
END;
$$
LANGUAGE plpgsql;

--Для теста создадим скалярные функции: с параметрами и без параметров.

CREATE OR REPLACE FUNCTION add_numbers(a INT, b INT) RETURNS INT AS
$$
BEGIN
    RETURN a + b;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dif_numbers(a INT, b INT) RETURNS INT AS
$$
BEGIN
    RETURN a - b;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_random_number() RETURNS INT AS
$$
DECLARE
    random_number INT;
BEGIN
    random_number := floor(random() * 100) + 1; 
    RETURN random_number;
END;
$$
LANGUAGE plpgsql;

-- Тестовая транзакция 
DO $$ 
DECLARE
    num_functions INT;
    function_info TEXT[];
BEGIN
    CALL get_scalar_functions_info(num_functions, function_info);
    RAISE NOTICE 'Found % scalar functions: %', num_functions, function_info;

END $$;


-- Выводим список всех функций и процедур БД
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public';


--3 Создать хранимую процедуру с выходным параметром, которая уничтожает все SQL DML триггеры в текущей базе данных.
-- Выходной параметр возвращает количество уничтоженных триггеров.

CREATE OR REPLACE PROCEDURE remove_public_triggers(OUT num_destroyed_triggers INT) AS
$$
DECLARE
    trg_name   TEXT;
    table_name TEXT;
BEGIN
    num_destroyed_triggers := 0;

    FOR trg_name, table_name IN (SELECT DISTINCT trigger_name, event_object_table
                                 FROM information_schema.triggers
                                 WHERE trigger_schema = 'public')
    LOOP
        EXECUTE CONCAT('DROP TRIGGER IF EXISTS ', trg_name, ' ON ', table_name);
        num_destroyed_triggers := num_destroyed_triggers + 1;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


-- Для теста 
-- Создание таблиц
CREATE TABLE public.test_table1 (
    id serial PRIMARY KEY,
    value INT
);

CREATE TABLE public.test_table2 (
    id serial PRIMARY KEY,
    value INT
);

-- Создание триггеров 
CREATE OR REPLACE FUNCTION trg_before_insert_test_table1()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Trigger trg_before_insert_test_table1 fired';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_before_insert_test_table1
BEFORE INSERT ON public.test_table1
FOR EACH ROW EXECUTE FUNCTION trg_before_insert_test_table1();

CREATE OR REPLACE FUNCTION trg_before_update_test_table2()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Trigger trg_before_update_test_table2 fired';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_before_update_test_table2
BEFORE UPDATE ON public.test_table2
FOR EACH ROW EXECUTE FUNCTION trg_before_update_test_table2();

SELECT trigger_name FROM information_schema.triggers;

--Тестовая транзакция
DO
$$
DECLARE
    num_triggers INT;
BEGIN
    CALL remove_public_triggers(num_triggers);
    RAISE NOTICE '% of triggers removed', num_triggers;
END
$$;

--4 Создать хранимую процедуру с входным параметром, которая выводит имена и описания типа объектов (только хранимых процедур и скалярных функций), 
--в тексте которых на языке SQL встречается строка, задаваемая параметром процедуры.

--Вариант 1. FUNCTION
--Вместо использования OUT параметров, можно воспользоваться FUNCTION, которая возвращает набор результатов в виде таблицы.

CREATE OR REPLACE FUNCTION fn_search_objects1(
    IN search_string TEXT
)
RETURNS TABLE (object_name TEXT, object_type TEXT)
AS $$
BEGIN
    RETURN QUERY
    SELECT routine_name::TEXT, routine_type::TEXT
    FROM information_schema.routines
    WHERE routine_definition ILIKE '%' || search_string || '%'
        AND routine_type IN ('FUNCTION', 'PROCEDURE')
        AND specific_schema = 'public';

    IF NOT FOUND THEN
        RETURN;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Тестовый запрос функции ('test', 'number')
SELECT * FROM fn_search_objects1('name'); 

--Вариант 2. PROCEDURE

CREATE OR REPLACE PROCEDURE sp_search_objects2(
    IN search_string TEXT,
    OUT object_name TEXT,
    OUT object_type TEXT
)
AS
$$
DECLARE
    result_record RECORD;
BEGIN
    -- Создаем временную таблицу для хранения результатов
    CREATE TEMP TABLE temp_result AS
    SELECT DISTINCT routine_name::TEXT, routine_type::TEXT
    FROM information_schema.routines
    WHERE routine_definition ILIKE '%' || search_string || '%'
        AND routine_type IN ('PROCEDURE', 'FUNCTION')
        AND specific_schema = 'public';

    -- Выводим результаты из временной таблицы
    FOR result_record IN (SELECT * FROM temp_result)
    LOOP
        -- Присваиваем значения OUT-параметрам
        object_name := result_record.routine_name;
        object_type := result_record.routine_type;

        RAISE NOTICE 'Object Name: %, Object Type: %', object_name, object_type;
    END LOOP;

    -- Удаляем временную таблицу
    DROP TABLE IF EXISTS temp_result;
END;
$$ LANGUAGE plpgsql;


-- Тест со строкой поиска ('test', 'number')
DO $$ 
DECLARE
    result_name TEXT;
    result_type TEXT;
BEGIN
    CALL sp_search_objects2('name', result_name, result_type);

END $$;

