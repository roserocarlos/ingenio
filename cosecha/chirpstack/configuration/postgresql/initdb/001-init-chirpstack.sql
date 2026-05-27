-- Crear base de datos y usuario para ChirpStack
CREATE ROLE chirpstack WITH LOGIN PASSWORD 'chirpstack';
CREATE DATABASE chirpstack WITH OWNER chirpstack;

-- Extensiones requeridas por ChirpStack v4 (gin_trgm_ops para índices de búsqueda)
\connect chirpstack
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
GRANT ALL ON SCHEMA public TO chirpstack;
