DROP TYPE IF EXISTS agent_kind CASCADE;
CREATE TYPE agent_kind as ENUM ('denizen','fixture');

DROP TABLE IF EXISTS agents CASCADE;
CREATE TABLE agents
  ( agent_id SERIAL CONSTRAINT agentpk PRIMARY KEY
  , agent agent_kind NOT NULL
  , name TEXT UNIQUE NOT NULL
  );

ALTER TABLE users ALTER COLUMN user_id DROP DEFAULT;
ALTER TABLE users ADD FOREIGN KEY (user_id) REFERENCES agents(agent_id);
ALTER TABLE users DROP COLUMN player_name;
