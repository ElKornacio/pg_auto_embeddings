-- pg_auto_embeddings v1.2.41

-- 1. Create schema for storing data of pg_auto_embeddings
CREATE SCHEMA pgae;

-- 2. Create table: credentials to store server url and appId/appSecret
CREATE TABLE pgae.credentials (
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
CREATE TABLE pgae.auto_embeddings (
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
CREATE PROCEDURE pgae.pgae_save_credentials_internal(
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
        server_url = appServer,
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

CREATE PROCEDURE pgae.pgae_init_credentials_internal(
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
        OPTIONS (host %L, port %L, dbname %L)', appServer, appPort, 'pgae');

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
    DROP SERVER pgae_login_server;
END;
$$;

CREATE PROCEDURE pgae.pgae_recreate_fdw_internal()
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

    EXECUTE format('CREATE SERVER pgae_server
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (host ''%L'', port ''%L'', dbname ''%L'')', serverHost, serverPort, userDatabase);

    EXECUTE format('CREATE USER MAPPING FOR PUBLIC
        SERVER pgae_server
        OPTIONS (user ''%L'', password ''%L'')', userLogin, userPassword);

    EXECUTE format('CREATE FOREIGN TABLE pgae.embeddings (
        text_val text,
        model_name text,
        api_key text,
        embedding vector(128)
    )
        SERVER pgae_server
        OPTIONS (schema_name ''%L'', table_name ''%L'')', userSchema, userTable);
END;
$$;

CREATE OR REPLACE FUNCTION pgae.pgae_embedding_internal(new_value TEXT)
RETURNS vector(128) AS $$
DECLARE
    model_name TEXT;
    api_key TEXT;
    updated_embedding vector(128);
BEGIN
    SELECT
        model_name,
        api_key
    FROM
        pgae.credentials
    INTO
        model_name,
        api_key;

    -- Execute the update and capture the RETURNING value into the variable
    UPDATE pgae.embeddings
    SET
        text_val = new_value,
        model_name = model_name,
        api_key = api_key
    RETURNING embedding INTO updated_embedding;

    -- Return the captured value
    RETURN updated_embedding;
END;
$$ LANGUAGE plpgsql;

CREATE PROCEDURE pgae.pgae_init_internal(appServer TEXT, appPort TEXT, modelName TEXT, apiKey TEXT)
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
CREATE PROCEDURE pgae_init(modelName TEXT, apiKey TEXT)
LANGUAGE plpgsql AS $$
BEGIN
   CALL pgae.pgae_init_internal('pgae.elkornacio.com', '13070', modelName, apiKey);
END;
$$;

CREATE PROCEDURE pgae_init_onprem(appServer TEXT, appPort TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    CALL pgae.pgae_init_internal(appServer, appPort, 'default', '');
END;
$$;

CREATE FUNCTION pgae_embedding(text_val TEXT)
RETURNS vector(128) AS $$
BEGIN
    RETURN pgae.pgae_embedding_internal(text_val);
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
        NEW."%I" := pgae.pgae_embedding_internal(NEW."%I");
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

-- 5. Create procedure: pgae_delete_auto_embedding(source_schema, source_table, source_col, destination_col);