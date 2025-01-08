import { Column, Entity, Index, PrimaryColumn, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class LoginEntity {
	@PrimaryGeneratedColumn('uuid')
	id!: string;

	@Index()
	@Column({ type: 'varchar', length: 255 })
	ip!: string;

	@Column({ type: 'varchar', length: 255 })
	user_login!: string;

	@Column({ type: 'varchar', length: 255 })
	user_password!: string;

	@Column({ type: 'varchar', length: 255 })
	user_table!: string;
}
