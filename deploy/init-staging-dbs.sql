-- Create separate databases for each Phoenix node in the staging cluster.
-- This script is mounted into the PostgreSQL container at
-- /docker-entrypoint-initdb.d/ and runs automatically on first start.

CREATE DATABASE cairn_node_a;
CREATE DATABASE cairn_node_b;

-- Grant full privileges to the cairn user on both databases.
GRANT ALL PRIVILEGES ON DATABASE cairn_node_a TO cairn;
GRANT ALL PRIVILEGES ON DATABASE cairn_node_b TO cairn;

-- Ensure the cairn user owns the public schema in each database
-- so that Ecto migrations can create tables without issues.
\connect cairn_node_a
GRANT ALL ON SCHEMA public TO cairn;

\connect cairn_node_b
GRANT ALL ON SCHEMA public TO cairn;
