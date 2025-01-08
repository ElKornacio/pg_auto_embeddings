import { Pool } from 'pg';

export const initDatabase = async (pool: Pool) => {
	console.log(`Creating extension: postgres_fdw`);
	await pool.query(`
        CREATE EXTENSION IF NOT EXISTS postgres_fdw;
    `);

	console.log(`Creating extension: http`);
	await pool.query(`
        CREATE EXTENSION IF NOT EXISTS http;
    `);

	console.log(`Creating extension: vector`);
	await pool.query(`
        CREATE EXTENSION IF NOT EXISTS vector;
    `);

	console.log(`Creating initial user: initial_user/initial_password`);
	await pool.query(`
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT FROM pg_catalog.pg_roles WHERE rolname = 'initial_user'
            ) THEN
                CREATE USER initial_user WITH PASSWORD 'initial_password';
            END IF;
        END
        $$;
    `);

	console.log(`Creating view: login`);
	await pool.query(`
        CREATE VIEW login AS
            SELECT
                user_login,
                user_password,
                user_database,
                user_schema,
                user_table
            FROM
                (
                    SELECT
                        *
                    FROM
                        jsonb_populate_record(
                            NULL::record,
                            (
                                SELECT content::jsonb
                                FROM http_get(CONCAT('http://localhost:3000/login?ip=', urlencode(inet_client_addr()::text)))
                            )
                        ) AS t(
                            user_login TEXT,
                            user_password TEXT,
                            user_database TEXT,
                            user_schema TEXT,
                            user_table TEXT
                        )
                )
    `);

	console.log(`Granting initial_user select access to login view`);
	await pool.query(`GRANT SELECT ON login TO initial_user`);
};

export const createUser = async (pool: Pool, user: string, password: string) => {
	console.log('Initializing new user');
	await pool.query(`CREATE USER ${user} WITH PASSWORD '${password}'`);
	console.log('User created');
};

export const createEmbeddingTable = async (pool: Pool, user: string, table: string) => {
	console.log('Initializing new embedding table for user: ', user);

	console.log(`Creating table: ${table}`);
	await pool.query(`CREATE TABLE ${table} (
        text_val text,
        model_name text,
        api_key text,
        embedding vector(128)    
    )`);

	console.log('Create empty row');
	await pool.query(`INSERT INTO ${table} (text_val, model_name, api_key) VALUES ('', '', '')`);

	// give update permission to user
	console.log(`Granting update permission to user: ${user}`);
	await pool.query(`GRANT UPDATE, SELECT ON TABLE ${table} TO ${user}`);

	// INSERT INTO public.request_log_test ("current_user", client_ip, client_port, client_app, connection_start, connection_state) SELECT
	//             usename AS current_user,             -- Current PostgreSQL user
	//             inet_client_addr() AS client_ip,     -- Client's IP address
	//             inet_client_port() AS client_port,   -- Client's port number
	//             application_name AS client_app,      -- Application name of the client
	//             backend_start AS connection_start,   -- Time the connection started
	//             state AS connection_state            -- Current state of the connection
	//         FROM pg_stat_activity
	//         WHERE pid = pg_backend_pid();            -- Filter for the current session

	// create trigger function
	console.log(`Creating trigger function: ${table}_trigger_func`);
	await pool.query(`
        CREATE OR REPLACE FUNCTION ${table}_trigger_func()
        RETURNS TRIGGER
        LANGUAGE plpgsql
        AS $$
        DECLARE
            embedding_text text;
        BEGIN
            SELECT
                embedding_vec
            FROM
                jsonb_populate_record(
                    NULL::record,
                    (
                        SELECT content::jsonb
                        FROM public.http_get(
                            CONCAT(
                                'http://localhost:3000/embedding?',
                                'ip=',
                                public.urlencode(inet_client_addr()::text),
                                '&text=',
                                public.urlencode(NEW.text_val),
                                '&model=',
                                public.urlencode(NEW.model_name),
                                '&api_key=',
                                public.urlencode(NEW.api_key)
                            )
                        )
                    )
                ) AS t(
                    embedding_vec TEXT
                )
            INTO embedding_text;

            NEW.embedding := embedding_text::public.vector(128);
            NEW.text_val := '';
            NEW.model_name := '';
            NEW.api_key := '';
            RETURN NEW;
        END;
        $$;
    `);

	console.log(`Creating trigger: ${table}_trigger`);
	await pool.query(`
        CREATE TRIGGER ${table}_trigger
        BEFORE INSERT OR UPDATE ON ${table}
        FOR EACH ROW EXECUTE PROCEDURE ${table}_trigger_func();
    `);
};
