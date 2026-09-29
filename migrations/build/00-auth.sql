DROP TYPE IF EXISTS account_status CASCADE;
CREATE TYPE account_status as ENUM ('active','inactive');

DROP TYPE IF EXISTS allowed_action CASCADE;
CREATE TYPE allowed_action as ENUM ('dsl');

DROP TYPE IF EXISTS role_name CASCADE;
CREATE TYPE role_name as ENUM ('player','wizard','admin');

DROP TABLE IF EXISTS roles CASCADE;
CREATE TABLE roles
  ( role_id SERIAL CONSTRAINT rolepk PRIMARY KEY
  , name role_name UNIQUE NOT NULL
  , role_permissions allowed_action[]
  , created_at timestamp with time zone NOT NULL
  , updated_at timestamp with time zone NOT NULL
  );

DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users
  ( user_id SERIAL CONSTRAINT upk PRIMARY KEY
  , status account_status NOT NULL
  , role_id INT NOT NULL REFERENCES roles(role_id)
  , activated_on timestamp with time zone NOT NULL
  , inactivated_on timestamp with time zone
    CONSTRAINT require_inactivated_on
      CHECK (status <> 'inactive' OR inactivated_on IS NOT NULL)
  );

DROP TABLE IF EXISTS credentials CASCADE;
CREATE TABLE credentials
  ( user_id INT UNIQUE NOT NULL REFERENCES users(user_id)
  , player_name TEXT UNIQUE NOT NULL
  , authentik_user_id uuid UNIQUE NOT NULL
  );

DROP TABLE IF EXISTS tokens CASCADE;
CREATE TABLE tokens
  ( token_digest bytea CONSTRAINT tpk PRIMARY KEY
  , user_id INT NOT NULL REFERENCES users(user_id)
  , created timestamp with time zone NOT NULL
  , expires_at timestamp with time zone NOT NULL
  );

DROP FUNCTION IF EXISTS remove_inactive_tokens;

CREATE FUNCTION remove_inactive_tokens() RETURNS trigger AS $$
  BEGIN
    IF NEW.status = 'inactive' THEN
      DELETE FROM tokens WHERE user_id = NEW.user_id;
    END IF;

    RETURN NULL;
  END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS remove_inactive_tokens ON users;

CREATE TRIGGER remove_inactive_tokens AFTER UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION remove_inactive_tokens();

INSERT INTO roles (name, role_permissions, created_at, updated_at) VALUES
    ('player', ARRAY[]::allowed_action[], now(), now())
  , ('wizard', ARRAY['dsl']::allowed_action[], now(), now())
  , ('admin', ARRAY[]::allowed_action[], now(), now());
