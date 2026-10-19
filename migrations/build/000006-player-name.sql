ALTER TABLE users ADD COLUMN player_name TEXT UNIQUE NOT NULL;
ALTER TABLE credentials DROP COLUMN player_name;
