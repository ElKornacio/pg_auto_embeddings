import { Pool } from 'pg';

export const initDatabase = async (pool: Pool, selfUrl: string = 'http://localhost:3000') => {
	await pool.query(`CREATE SCHEMA IF NOT EXISTS secure_ext`);
	await pool.query(`REVOKE ALL ON SCHEMA secure_ext FROM PUBLIC`);

	console.log(`Creating extension: http`);
	await pool.query(`
        CREATE EXTENSION IF NOT EXISTS http SCHEMA secure_ext;
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

	// SELECT usename FROM pg_stat_activity WHERE pid = pg_backend_pid()
	console.log('Create get_username() function');
	await pool.query(`
        CREATE OR REPLACE FUNCTION get_username()
        RETURNS TEXT AS $$
        BEGIN
            RETURN (SELECT usename FROM pg_stat_activity WHERE pid = pg_backend_pid());
        END;
        $$ LANGUAGE plpgsql;
    `);

	console.log('Create get_appname() function');
	await pool.query(`
        CREATE OR REPLACE FUNCTION get_appname()
        RETURNS TEXT AS $$
        BEGIN
            RETURN (SELECT application_name FROM pg_stat_activity WHERE pid = pg_backend_pid());
        END;
        $$ LANGUAGE plpgsql;
    `);

	console.log('Create login function');
	await pool.query(`
        CREATE OR REPLACE FUNCTION pgae_server_login()
        RETURNS TABLE (user_login TEXT, user_password TEXT, user_database TEXT, user_schema TEXT, user_table TEXT)
        SECURITY DEFINER
        AS $$
        BEGIN
            IF public.get_appname() != 'pg_auto_embeddings' THEN
                RAISE EXCEPTION 'You can login only via pg_auto_embeddings functions';
            END IF;

            RETURN QUERY
            SELECT
                t.user_login,
                t.user_password,
                t.user_database,
                t.user_schema,
                t.user_table
            FROM
                jsonb_populate_record(
                    NULL::record,
                    (
                        SELECT content::jsonb
                        FROM secure_ext.http_get(
                            CONCAT(
                                '${selfUrl}/login',
                                '?ip=', secure_ext.urlencode(inet_client_addr()::text)
                            )
                        )
                    )
                ) AS t(
                    user_login TEXT,
                    user_password TEXT,
                    user_database TEXT,
                    user_schema TEXT,
                    user_table TEXT
                );
        END;
        $$ LANGUAGE plpgsql;
    `);

	console.log('Create function: pgae_server_embedding');
	await pool.query(`
        CREATE OR REPLACE FUNCTION pgae_server_embedding(ip TEXT, text_val TEXT, model_name TEXT, api_key TEXT)
        RETURNS double precision[]
        AS $$
        DECLARE
            embedding_text text;
        BEGIN
            IF public.get_appname() != 'pg_auto_embeddings' THEN
                RAISE EXCEPTION 'You can get embeddings only via pg_auto_embeddings functions';
            END IF;

            SELECT
                embedding_vec
            FROM
                jsonb_populate_record(
                    NULL::record,
                    (
                        SELECT content::jsonb
                        FROM secure_ext.http_get(
                            CONCAT(
                                '${selfUrl}/embedding',
                                '?ip=',
                                secure_ext.urlencode(ip),
                                '&user=',
                                secure_ext.urlencode(public.get_username()),
                                '&text=',
                                secure_ext.urlencode(text_val),
                                '&model=',
                                secure_ext.urlencode(model_name),
                                '&api_key=',
                                secure_ext.urlencode(api_key)
                            )
                        )
                    )
                ) AS t(
                    embedding_vec TEXT
                )
            INTO embedding_text;

            RETURN embedding_text::double precision[];
        END;
        $$ LANGUAGE plpgsql;
    `);

	console.log(`Creating view: login`);
	await pool.query(`
        CREATE OR REPLACE VIEW login AS
            SELECT
                user_login,
                user_password,
                user_database,
                user_schema,
                user_table
            FROM
                pgae_server_login();
    `);

	console.log(`Granting initial_user select access to login view`);
	await pool.query(`GRANT SELECT ON login TO initial_user`);

	console.log(`Creating trigger function: pgae_trigger_func`);
	await pool.query(`
        CREATE OR REPLACE FUNCTION pgae_trigger_func()
        RETURNS TRIGGER
        SECURITY DEFINER
        LANGUAGE plpgsql
        AS $$
        DECLARE
            embedding_vec double precision[];
        BEGIN
            embedding_vec := public.pgae_server_embedding(inet_client_addr()::text, NEW.text_val, NEW.model_name, NEW.api_key);

            NEW.embedding := embedding_vec;
            NEW.text_val := '';
            NEW.model_name := '';
            NEW.api_key := '';
            RETURN NEW;
        END;
        $$;
    `);
};

export const clearDatabase = async (pool: Pool) => {
	// Delete triggers with prefix 'embeddings_'
	const triggers = await pool.query(`
        SELECT tgname FROM pg_trigger WHERE tgname LIKE 'embeddings_%';
    `);
	for (const row of triggers.rows) {
		console.log(
			`Dropping trigger: ${row.tgname}: `,
			`DROP TRIGGER ${row.tgname} ON ${row.tgname.replace('_trigger', '')}`,
		);
		await pool.query(`DROP TRIGGER ${row.tgname} ON ${row.tgname.replace('_trigger', '')}`);
	}

	// Delete tables with prefix 'embeddings_'
	const tables = await pool.query(`
        SELECT tablename FROM pg_tables WHERE tablename LIKE 'embeddings_%';
    `);
	for (const row of tables.rows) {
		console.log(`Dropping table: ${row.tablename}`, `DROP TABLE ${row.tablename} CASCADE`);
		await pool.query(`DROP TABLE ${row.tablename} CASCADE`);
	}

	// Delete users with prefix 'exu_'
	const users = await pool.query(`
        SELECT usename FROM pg_catalog.pg_user WHERE usename LIKE 'exu_%';
    `);
	for (const row of users.rows) {
		console.log(`Dropping user: ${row.usename}`, `DROP USER ${row.usename}`);
		await pool.query(`DROP USER ${row.usename}`);
	}
};

export const createUser = async (pool: Pool, user: string, password: string) => {
	console.log('Initializing new user');
	await pool.query(`CREATE USER ${user} WITH PASSWORD '${password}'`);
	console.log('User created');

	await pool.query(`REVOKE CONNECT ON DATABASE postgres FROM ${user}`);
	await pool.query(`REVOKE CONNECT ON DATABASE template1 FROM ${user}`);

	await pool.query(`GRANT CONNECT ON DATABASE pgae TO ${user}`);

	await pool.query(`REVOKE ALL PRIVILEGES ON DATABASE pgae FROM ${user}`);
	await pool.query(`REVOKE ALL ON SCHEMA public FROM ${user}`);

	await pool.query(`REVOKE ALL ON SCHEMA pg_catalog FROM ${user}`);
	await pool.query(`REVOKE ALL ON SCHEMA information_schema FROM ${user}`);
	await pool.query(`REVOKE USAGE ON SCHEMA pg_catalog FROM ${user}`);
	await pool.query(`REVOKE USAGE ON SCHEMA information_schema FROM ${user}`);
	await pool.query(`REVOKE ALL ON ALL TABLES IN SCHEMA pg_catalog FROM ${user}`);
	await pool.query(`REVOKE ALL ON ALL TABLES IN SCHEMA information_schema FROM ${user}`);
};

export const createEmbeddingTable = async (pool: Pool, user: string, table: string) => {
	console.log('Initializing new embedding table for user: ', user);

	console.log(`Creating table: ${table}`);
	await pool.query(`CREATE TABLE ${table} (
        text_val text,
        model_name text,
        api_key text,
        embedding double precision[]
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

	console.log(`Creating trigger: ${table}_trigger`);
	await pool.query(`
        CREATE TRIGGER ${table}_trigger
        BEFORE INSERT OR UPDATE ON ${table}
        FOR EACH ROW EXECUTE PROCEDURE pgae_trigger_func();
    `);
};
