# Use the official Node.js image
FROM node:20-bullseye

# Add a label to the Docker image
LABEL maintainer="ek@elkornacio.com"

# Set the working directory
WORKDIR /app

# Install PostgreSQL 17
RUN apt-get update && \
    apt-get install -y wget gnupg2 && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y postgresql-17 postgresql-contrib && \
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/17/main/postgresql.conf && \
    sed -i "s/#max_connections = 100/max_connections = 100000/g" /etc/postgresql/17/main/postgresql.conf && \
    echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/17/main/pg_hba.conf && \
    rm -rf /var/lib/apt/lists/*

# Install the postgresql-http extension
RUN apt-get update && \
    apt-get install -y postgresql-17-http && \
    rm -rf /var/lib/apt/lists/*

# Install the pgvector extension
RUN apt-get update && \
    apt-get install -y postgresql-17-pgvector && \
    rm -rf /var/lib/apt/lists/*

COPY src/init/docker-init.sh /root/docker-init.sh
RUN chmod 755 /root/docker-init.sh

COPY package.json /app
COPY tsconfig.json /app

# Install dependencies
RUN npm install

# Copy Node.js application files
COPY dist /app/dist
COPY src /app/src

# RUN npm run build

# Start PostgreSQL and Node.js server
CMD service postgresql start && /root/docker-init.sh && node dist/index.js

# docker build -t custom-node-postgres:latest .
