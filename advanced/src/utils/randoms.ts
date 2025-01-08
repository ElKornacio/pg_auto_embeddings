import { randomUUID } from 'crypto';

export const randomLogin = () => {
	return 'u' + randomUUID().replaceAll('-', '');
};

export const randomPassword = () => {
	return 'p' + randomUUID().replaceAll('-', '');
};

export const randomTable = () => {
	const alphabet = 'abcdefghijklmnopqrstuvwxyz';
	const suffixLength = 8;
	const randomSuffix = Array.from(
		{ length: suffixLength },
		() => alphabet[Math.floor(Math.random() * alphabet.length)],
	).join('');
	return `embeddings_${randomSuffix}`;
};
