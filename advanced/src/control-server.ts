import express from 'express';
import { Pool } from 'pg';
import { initDatabase } from './sql-utils';
import { clearDatabase } from './sql-utils';

export async function runControlServer(port: number, host: string, pool: Pool) {
	const app = express();

	app.get('/recreate-database', async (req, res) => {
		try {
			await clearDatabase(pool);
			await initDatabase(pool, process.env.SELF_URL);
			res.send('Database recreated');
		} catch (error) {
			console.error(error);
			res.status(500).send('Error recreating database');
		}
	});

	app.listen(port, host, () => {
		console.log(`Control server is running on port ${port} and host ${host}`);
	});
}
