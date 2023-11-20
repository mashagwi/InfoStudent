-- 1) Создать хранимую процедуру, которая, 
--не уничтожая базу данных, уничтожает все те таблицы текущей базы данных, имена которых начинаются с фразы 'TableName'.

CREATE OR REPLACE PROCEDURE drop_tables_with_prefix(prefix_to_drop TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    cur_table_name TEXT;
    drop_query TEXT;
BEGIN
    -- Получаем список таблиц в текущей базе данных
    FOR cur_table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE prefix_to_drop || '%') 
    LOOP
        -- Формируем запрос для удаления таблицы
        drop_query := 'DROP TABLE IF EXISTS ' || cur_table_name || ' CASCADE';
        EXECUTE drop_query;
    END LOOP;
END;
$$;

CALL drop_tables_with_prefix('tablename');

--DROP PROCEDURE IF EXISTS drop_tables_with_prefix CASCADE;

--Для теста

-- CREATE TABLE TableName1 (id serial PRIMARY KEY, name VARCHAR(255));
-- CREATE TABLE TableName2 (id serial PRIMARY KEY, description VARCHAR(255));
-- CREATE TABLE OtherTable (id serial PRIMARY KEY, description VARCHAR(255));

-- 2) Создать хранимую процедуру с выходным параметром, которая выводит список имен и параметров всех скалярных  
--SQL функций пользователя в текущей базе данных. Имена функций без параметров не выводить. 
--Имена и список параметров должны выводиться в одну строку. 
--Выходной параметр возвращает количество найденных функций.

CREATE OR REPLACE PROCEDURE get_scalar_functions_info(
    OUT num_functions INT,
    OUT function_info TEXT
) AS
$$
DECLARE
    function_name   TEXT;
    function_params TEXT;
    func_record     RECORD;
BEGIN
    num_functions := 0;
    function_info := '';

    FOR func_record IN
        SELECT p.proname AS function_name, pg_get_function_identity_arguments(p.oid) AS function_params
        FROM pg_proc p
                 JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proargtypes IS NOT NULL
        LOOP
            function_name := func_record.function_name;
            function_params := func_record.function_params;
            
            IF function_params != '' THEN
                num_functions := num_functions + 1;
                function_info := function_info || function_name || '(' || function_params || '), ';
            END IF;
        END LOOP;

    IF LENGTH(function_info) > 2 THEN
        function_info := SUBSTRING(function_info, 1, LENGTH(function_info) - 2);
    END IF;
END;
$$
LANGUAGE plpgsql;

DO
$$
DECLARE
    num_functions INT;
    function_info TEXT;
BEGIN
    CALL get_scalar_functions_info(num_functions, function_info);
    RAISE NOTICE 'Found % scalar functions: %', num_functions, function_info;
END
$$;

--Для теста. В этом и предыдущем заданиях уже созданы функции.
-- SELECT proname, pg_get_function_identity_arguments(oid) AS arguments
-- FROM pg_proc
-- WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');


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

DO
$$
DECLARE
    num_triggers INT;
BEGIN
    CALL remove_public_triggers(num_triggers);
    RAISE NOTICE 'Удалено % триггеров', num_triggers;
END
$$;


-- Для теста 
-- Создание таблиц для тестирования
-- CREATE TABLE public.test_table1 (
--     id serial PRIMARY KEY,
--     value INT
-- );

-- CREATE TABLE public.test_table2 (
--     id serial PRIMARY KEY,
--     value INT
-- );

-- Создание триггеров для тестирования
-- CREATE OR REPLACE FUNCTION trg_before_insert_test_table1()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     RAISE NOTICE 'Trigger trg_before_insert_test_table1 fired';
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_before_insert_test_table1
-- BEFORE INSERT ON public.test_table1
-- FOR EACH ROW EXECUTE FUNCTION trg_before_insert_test_table1();

-- CREATE OR REPLACE FUNCTION trg_before_update_test_table2()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     RAISE NOTICE 'Trigger trg_before_update_test_table2 fired';
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_before_update_test_table2
-- BEFORE UPDATE ON public.test_table2
-- FOR EACH ROW EXECUTE FUNCTION trg_before_update_test_table2();

-- SELECT trigger_name FROM information_schema.triggers;

--4 Создать хранимую процедуру с входным параметром, которая выводит имена и описания типа объектов (только хранимых процедур и скалярных функций), 
--в тексте которых на языке SQL встречается строка, задаваемая параметром процедуры.

CREATE OR REPLACE FUNCTION fn_show_info(search_string TEXT)
RETURNS TABLE (name TEXT, type TEXT)
AS
$$
BEGIN
    RETURN QUERY
    SELECT routine_name::TEXT,
           routine_type::TEXT
    FROM information_schema.routines
    WHERE routine_name::TEXT LIKE '%' || search_string || '%'
      AND specific_schema NOT LIKE 'pg_%'  -- Исключаем системные схемы
      AND specific_schema NOT LIKE 'information_schema';
END
$$ LANGUAGE plpgsql;

SELECT * FROM fn_show_info('test');

DROP FUNCTION fn_show_info(text);

-- -- Проверяем имя и тип всех функций и процедур, которые были созданы.
-- SELECT routine_name, routine_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public';