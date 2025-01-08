import { DataSource, Repository } from 'typeorm';
import fs from 'fs';
//
import { LoginEntity } from './entities/Login.entity';

export interface ISqliteStorage {
	type: 'sqlite';
	filePath: string;
}

export interface IPostgresStorage {
	type: 'postgres';
	host: string;
	port: number;
	username: string;
	password: string;
	database: string;
	schema?: string;
	ssl?: string | false;
}

export type IDatabaseStorage = ISqliteStorage | IPostgresStorage;

export let loginRepository: Repository<LoginEntity>;

export let dataSource: DataSource;

export const initDataSource = async (storage: IDatabaseStorage) => {
	const common = {
		// logging: true,
		entities: [LoginEntity],
		subscribers: [],
		migrations: [],
		synchronize: process.env.DATABASE_SYNC === 'true',
	};

	if (storage.type === 'postgres') {
		dataSource = new DataSource({
			type: 'postgres',
			host: storage.host,
			port: storage.port,
			username: storage.username,
			password: storage.password,
			database: storage.database,
			schema: storage.schema,
			ssl: storage.ssl
				? {
						ca: fs.readFileSync(storage.ssl, 'utf-8'),
				  }
				: false,
			...common,
		});
	} else if (storage.type === 'sqlite') {
		dataSource = new DataSource({
			type: 'sqlite',
			database: storage.filePath,
			...common,
		});
	}

	await dataSource.initialize();

	loginRepository = dataSource.getRepository(LoginEntity);
};
