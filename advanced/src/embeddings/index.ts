export const getEmbedding = async (text: string, model: string, api_key: string) => {
	return `[${new Array(128)
		.fill(0)
		.map(() => Math.random())
		.join(',')}]`;
};
