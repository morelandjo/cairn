-- Create separate databases for each Phoenix node in the staging cluster.
-- This script is mounted into the PostgreSQL container at
-- /docker-entrypoint-initdb.d/ and runs automatically on first start.

CREATE DATABASE murmuring_node_a;
CREATE DATABASE murmuring_node_b;

-- Grant full privileges to the murmuring user on both databases.
GRANT ALL PRIVILEGES ON DATABASE murmuring_node_a TO murmuring;
GRANT ALL PRIVILEGES ON DATABASE murmuring_node_b TO murmuring;

-- Ensure the murmuring user owns the public schema in each database
-- so that Ecto migrations can create tables without issues.
\connect murmuring_node_a
GRANT ALL ON SCHEMA public TO murmuring;

\connect murmuring_node_b
GRANT ALL ON SCHEMA public TO murmuring;
