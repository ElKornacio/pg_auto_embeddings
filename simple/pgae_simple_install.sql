-- pg_auto_embeddings v1.2.41

-- 1. Create schema for storing data of pg_auto_embeddings
CREATE SCHEMA IF NOT EXISTS pgae;

-- 2. Create table: credentials to store server url and appId/appSecret
CREATE TABLE IF NOT EXISTS pgae.credentials (
    id int PRIMARY KEY DEFAULT 1,
    server_host TEXT NOT NULL,
    server_port TEXT NOT NULL,
    user_login TEXT NOT NULL,
    user_password TEXT NOT NULL,
    user_database TEXT NOT NULL,
    user_schema TEXT NOT NULL,
    user_table TEXT NOT NULL,
    model_name TEXT NOT NULL,
    api_key TEXT NOT NULL
);

-- 3. Create table: list of registered auto_embeddings (source_schema, source_table, source_col, target_col, embedding_type)
CREATE TABLE IF NOT EXISTS pgae.auto_embeddings (
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    source_col TEXT NOT NULL,
    target_col TEXT NOT NULL,
    PRIMARY KEY (source_schema, source_table, source_col, target_col)
);

-- functions:
-- bool create_auto_embedding(source_schema, source_table, source_col, destination_col);
-- bool delete_auto_embedding(source_schema, source_table, source_col, destination_col);
-- vector embedding(text);
-- --
-- bool pgae_init(text modelName, text apiKey)
-- bool pgae_init_onprem(text appServer, text appPort)

--------- INTERNAL PROCEDURES ---------
CREATE OR REPLACE PROCEDURE pgae.pgae_save_credentials_internal(
    appServer TEXT,
    appPort TEXT,
    userLogin TEXT,
    userPassword TEXT,
    userDatabase TEXT,
    userSchema TEXT,
    userTable TEXT,
    modelName TEXT,
    apiKey TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO
        pgae.credentials (
            id,
            server_host,
            server_port,
            user_login,
            user_password,
            user_database,
            user_schema,
            user_table,
            model_name,
            api_key
        )
    VALUES (
        1,
        appServer,
        appPort,
        userLogin,
        userPassword,
        userDatabase,
        userSchema,
        userTable,
        modelName,
        apiKey
    )
    ON CONFLICT (id) DO UPDATE SET
        server_host = appServer,
        server_port = appPort,
        user_login = userLogin,
        user_password = userPassword,
        user_database = userDatabase,
        user_schema = userSchema,
        user_table = userTable,
        model_name = modelName,
        api_key = apiKey;
END;
$$;

CREATE OR REPLACE PROCEDURE pgae.pgae_init_credentials_internal(
    appServer TEXT,
    appPort TEXT,
    modelName TEXT,
    apiKey TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    userLogin text;
    userPassword text;
    userDatabase text;
    userSchema text;
    userTable text;
BEGIN
    CREATE EXTENSION IF NOT EXISTS postgres_fdw;

    EXECUTE format('CREATE SERVER pgae_login_server
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (host %L, port %L, dbname %L, application_name %L)', appServer, appPort, 'pgae', 'pg_auto_embeddings');

    CREATE USER MAPPING FOR CURRENT_USER
    SERVER pgae_login_server
    OPTIONS (user 'initial_user', password 'initial_password');

    CREATE FOREIGN TABLE pgae.login (
        user_login text,
        user_password text,
        user_database text,
        user_schema text,
        user_table text
    )
    SERVER pgae_login_server
    OPTIONS (schema_name 'public', table_name 'login');

    -- SELECT * FROM pgae.login;
    -- select login and password from login table and save them into credentials table
    SELECT
        user_login,
        user_password,
        user_database,
        user_schema,
        user_table
    FROM
        pgae.login
    INTO
        userLogin,
        userPassword,
        userDatabase,
        userSchema,
        userTable;

    CALL pgae.pgae_save_credentials_internal(appServer, appPort, userLogin, userPassword, userDatabase, userSchema, userTable, modelName, apiKey);

    DROP FOREIGN TABLE pgae.login;
    DROP SERVER pgae_login_server CASCADE;
END;
$$;

CREATE OR REPLACE PROCEDURE pgae.pgae_recreate_fdw_internal()
LANGUAGE plpgsql AS $$
DECLARE
    serverHost TEXT;
    serverPort TEXT;
    userLogin TEXT;
    userPassword TEXT;
    userDatabase TEXT;
    userSchema TEXT;
    userTable TEXT;
BEGIN
    SELECT
        server_host,
        server_port,
        user_login,
        user_password,
        user_database,
        user_schema,
        user_table,
        model_name,
        api_key
    FROM
        pgae.credentials
    INTO
        serverHost,
        serverPort,
        userLogin,
        userPassword,
        userDatabase,
        userSchema,
        userTable;

    -- Drop the server if it exists
    IF EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'pgae_server') THEN
        EXECUTE 'DROP SERVER pgae_server CASCADE';
    END IF;

    -- Recreate the server
    EXECUTE format('CREATE SERVER pgae_server
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (host %L, port %L, dbname %L, application_name %L)', serverHost, serverPort, userDatabase, 'pg_auto_embeddings');

    EXECUTE format('CREATE USER MAPPING FOR PUBLIC
        SERVER pgae_server
        OPTIONS (user %L, password %L)', userLogin, userPassword);

    EXECUTE format('CREATE FOREIGN TABLE pgae.embeddings (
        text_val text,
        model_name text,
        api_key text,
        embedding double precision[]
    )
        SERVER pgae_server
        OPTIONS (schema_name %L, table_name %L)', userSchema, userTable);
END;
$$;

CREATE OR REPLACE FUNCTION pgae.pgae_embedding_internal(new_value TEXT)
RETURNS double precision[] AS $$
DECLARE
    cred_model_name TEXT;
    cred_api_key TEXT;
    updated_embedding double precision[];
BEGIN
    SELECT
        c.model_name,
        c.api_key
    FROM
        pgae.credentials AS c
    INTO
        cred_model_name,
        cred_api_key;

    -- Execute the update and capture the RETURNING value into the variable
    UPDATE pgae.embeddings
    SET
        text_val = new_value,
        model_name = cred_model_name,
        api_key = cred_api_key
    RETURNING embedding INTO updated_embedding;

    -- Return the captured value
    RETURN updated_embedding;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pgae.pgae_init_internal(appServer TEXT, appPort TEXT, modelName TEXT, apiKey TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    userLogin text;
    userPassword text;
BEGIN
    CALL pgae.pgae_init_credentials_internal(appServer, appPort, modelName, apiKey);

    -- now full credentials are saved into credentials table
    -- now we can create server and real user mapping

    CALL pgae.pgae_recreate_fdw_internal();
END;
$$;

---------- PUBLIC PROCEDURES ---------
CREATE OR REPLACE PROCEDURE pgae_init(modelName TEXT, apiKey TEXT)
LANGUAGE plpgsql AS $$
BEGIN
   CALL pgae.pgae_init_internal('pgae.elkornacio.com', '13070', modelName, apiKey);
END;
$$;

CREATE OR REPLACE PROCEDURE pgae_init_onprem(appServer TEXT, appPort TEXT, modelName TEXT, apiKey TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    CALL pgae.pgae_init_internal(appServer, appPort, modelName, apiKey);
END;
$$;

CREATE FUNCTION pgae_embedding(text_val TEXT)
RETURNS double precision[] AS $$
BEGIN
    RETURN pgae.pgae_embedding_internal(text_val);
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pgae_embedding_vec(text_val TEXT)
RETURNS vector AS $$
BEGIN
    RETURN pgae.pgae_embedding_internal(text_val)::vector;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgae_create_auto_embedding(source_schema TEXT, source_table TEXT, source_col TEXT, destination_col TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    trigger_name TEXT;
BEGIN
    -- 1. Check if the trigger already exists
    IF EXISTS (
        SELECT
            1
        FROM
            pgae.auto_embeddings
        WHERE
                source_schema = source_schema
            AND
                source_table = source_table
            AND
                source_col = source_col
            AND
                target_col = target_col
    ) THEN
        RETURN FALSE;
    END IF;

    -- 2. Create the trigger record
    INSERT INTO
        pgae.auto_embeddings
        (
            source_schema,
            source_table,
            source_col,
            target_col
        )
    VALUES
        (
            source_schema,
            source_table,
            source_col,
            target_col
        );

    -- 3. Put "<source_schema>_<source_table>_<source_col>_<target_col>" into a variable
    trigger_name := CONCAT(
        source_schema,
        '_', source_table,
        '_', source_col,
        '_', target_col
    );

    -- 3. Create the unique trigger function:
    EXECUTE format('CREATE OR REPLACE FUNCTION pgae_trigger_func_%I()
    RETURNS TRIGGER AS __
    BEGIN
        NEW."%I" := pgae.pgae_embedding_internal(NEW."%I")::vector;
        RETURN NEW;
    END;
    __ LANGUAGE plpgsql', trigger_name, target_col, source_col);

    -- 4. Create the unique trigger:
    EXECUTE format('CREATE TRIGGER pgae_trigger_%I
        AFTER INSERT OR UPDATE ON %I.%I
        FOR EACH ROW EXECUTE PROCEDURE pgae_trigger_func_%I()',
        trigger_name, source_schema, source_table, trigger_name);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgae_delete_auto_embedding(source_schema TEXT, source_table TEXT, source_col TEXT, destination_col TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    trigger_name TEXT;
BEGIN
    -- 1. Check if the trigger exists
    IF NOT EXISTS (
        SELECT
            1
        FROM
            pgae.auto_embeddings
        WHERE
                source_schema = source_schema
            AND
                source_table = source_table
            AND
                source_col = source_col
            AND
                target_col = target_col
    ) THEN
        RETURN FALSE;
    END IF;

    trigger_name := CONCAT(
        source_schema,
        '_', source_table,
        '_', source_col,
        '_', target_col
    );

    DELETE FROM
        pgae.auto_embeddings
    WHERE
            source_schema = source_schema
        AND
            source_table = source_table
        AND
            source_col = source_col
        AND
            target_col = target_col;

    EXECUTE format('DROP TRIGGER IF EXISTS pgae_trigger_%I ON %I.%I', trigger_name, source_schema, source_table);
    EXECUTE format('DROP FUNCTION IF EXISTS pgae_trigger_func_%I()', trigger_name);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pgae_self_destroy()
LANGUAGE plpgsql AS $$
DECLARE
    trigger_name TEXT;
    src_schema TEXT;
    src_table TEXT;
    src_col TEXT;
    tgt_col TEXT;
BEGIN
    -- Select all auto-embeddings
    FOR src_schema, src_table, src_col, tgt_col IN
        SELECT source_schema, source_table, source_col, target_col
        FROM pgae.auto_embeddings
    LOOP
        -- Construct trigger name
        trigger_name := CONCAT(src_schema, '_', src_table, '_', src_col, '_', tgt_col);

        -- Drop corresponding trigger functions and triggers
        EXECUTE format('DROP TRIGGER IF EXISTS pgae_trigger_%I ON %I.%I', trigger_name, src_schema, src_table);
        EXECUTE format('DROP FUNCTION IF EXISTS pgae_trigger_func_%I()', trigger_name);
    END LOOP;

    -- Drop FDW server
    IF EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'pgae_server') THEN
        EXECUTE 'DROP SERVER pgae_server CASCADE';
    END IF;

    -- Drop the whole pgae schema
    DROP SCHEMA pgae CASCADE;

    -- Drop all pgae public functions
    DROP PROCEDURE IF EXISTS pgae_init(TEXT, TEXT);
    DROP PROCEDURE IF EXISTS pgae_init_onprem(TEXT, TEXT, TEXT, TEXT);
    DROP FUNCTION IF EXISTS pgae_embedding(TEXT);
    DROP FUNCTION IF EXISTS pgae_embedding_vec(TEXT);
    DROP FUNCTION IF EXISTS pgae_create_auto_embedding(TEXT, TEXT, TEXT, TEXT);
    DROP FUNCTION IF EXISTS pgae_delete_auto_embedding(TEXT, TEXT, TEXT, TEXT);

    DROP PROCEDURE IF EXISTS pgae_self_destroy();
END;
$$;