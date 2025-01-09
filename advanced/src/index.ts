import 'dotenv/config';

import express from 'express';
import { Pool } from 'pg';
import { createEmbeddingTable, createUser, initDatabase } from './sql-utils';
import { initDataSource, loginRepository } from './database';
import { LoginEntity } from './entities/Login.entity';
import { randomLogin, randomTable } from './utils/randoms';
import { randomPassword } from './utils/randoms';
import { getEmbedding } from './embeddings';
import { runControlServer } from './control-server';

async function start() {
	console.log('Init internal database');

	await initDataSource({
		type: 'sqlite',
		filePath: ':memory:',
	});

	console.log('Starting server');

	const pool = new Pool({
		host: process.env.PG_HOST,
		port: Number(process.env.PG_PORT),
		user: process.env.PG_USERNAME,
		password: process.env.PG_PASSWORD,
		database: 'pgae',
		max: 3,
	});

	await initDatabase(pool, process.env.SELF_URL);

	const app = express();

	app.get('/embedding', async (req, res) => {
		try {
			const ip = req.query.ip as string;
			const user = req.query.user as string;
			const text = req.query.text as string;
			const model = req.query.model as string;
			const api_key = req.query.api_key as string;

			console.log('ip: ', ip);
			console.log('user: ', user);
			console.log('text: ', text);
			console.log('model: ', model);
			console.log('api_key: ', api_key);

			const embedding = await getEmbedding(text, model, api_key);

			console.log('embedding: ', embedding);

			res.json({ embedding_vec: '{' + embedding.join(',') + '}' });
		} catch (err) {
			console.error(err);
			res.status(500).send('Internal server error');
		}
	});

	app.get('/login', async (req, res) => {
		try {
			const ip = req.query.ip as string;
			if (!ip) {
				res.status(400).send('IP is required');
				return;
			}

			console.log('Login request from IP: ', ip);

			const login = new LoginEntity();
			login.ip = ip;
			login.user_login = randomLogin();
			login.user_password = randomPassword();
			login.user_table = randomTable();

			await loginRepository.save(login);

			await createUser(pool, login.user_login, login.user_password);
			await createEmbeddingTable(pool, login.user_login, login.user_table);

			res.json({
				user_login: login.user_login,
				user_password: login.user_password,
				user_database: 'pgae',
				user_schema: 'public',
				user_table: login.user_table,
			});
		} catch (err) {
			console.log('err: ', err);
			res.status(500).send('Internal server error');
		}
	});

	app.listen(Number(process.env.SERVER_PORT), process.env.SERVER_HOST || 'localhost', () => {
		console.log(
			`On-premise pg_auto_embeddings server is running on port ${process.env.SERVER_PORT} and host ${
				process.env.SERVER_HOST || 'localhost'
			}`,
		);
	});

	if (process.env.CONTROL_SERVER_PORT) {
		await runControlServer(
			Number(process.env.CONTROL_SERVER_PORT),
			process.env.CONTROL_SERVER_HOST || 'localhost',
			pool,
		);
	}
}

start();
