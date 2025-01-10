import OpenAI from 'openai';

export const getEmbedding = async (text: string, model: string, api_key: string) => {
	if (model.startsWith('openai-')) {
		return getEmbeddingOpenAI(text, model, api_key);
	} else if (model.startsWith('voyage-')) {
		return getEmbeddingVoyage(text, model, api_key);
	}

	return getNullVector();
};

export const getNullVector = () => {
	return new Array(128).fill(0).map(() => Math.random());
};

export const getEmbeddingOpenAI = async (text: string, model: string, api_key: string) => {
	const client = new OpenAI({
		apiKey: api_key, // This is the default and can be omitted
	});

	const cleanModelName = model.replace('openai-', '');

	const response = await client.embeddings.create({
		model: cleanModelName,
		input: text,
		encoding_format: 'float',
	});

	return response?.data[0]?.embedding || getNullVector();
};

export const getEmbeddingVoyage = async (text: string, model: string, api_key: string) => {
	const response = await fetch('https://api.voyageai.com/v1/embeddings', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json',
			'Authorization': `Bearer ${api_key}`,
		},
		body: JSON.stringify({
			input: [text],
			model,
		}),
	});

	const data = await response.json();

	return data?.data[0]?.embedding || getNullVector();
};
