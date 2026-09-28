DROP TYPE IF EXISTS account_status CASCADE;
CREATE TYPE account_status as ENUM ('active','inactive');

DROP TYPE IF EXISTS resource CASCADE;
CREATE TYPE resource as ENUM ('dsl');

DROP TYPE IF EXISTS action CASCADE;
CREATE TYPE action as ENUM ('create');

DROP TYPE IF EXISTS role_status CASCADE;
CREATE TYPE role_status as ENUM ('role_active','role_inactive');

CREATE OR REPLACE FUNCTION resource_actions() RETURNS jsonb
  RETURN '
    { "dsl": ["create"]
    }
  '::jsonb;

DROP TABLE IF EXISTS roles CASCADE;
CREATE TABLE roles
  ( role_id SERIAL CONSTRAINT rolepk PRIMARY KEY
  , name TEXT UNIQUE NOT NULL
  , created_at timestamp with time zone NOT NULL
  , updated_at timestamp with time zone NOT NULL
  , status role_status NOT NULL
  );

DROP TABLE IF EXISTS role_permissions;
CREATE TABLE role_permissions
  ( role_id INT REFERENCES roles(role_id) ON DELETE CASCADE
  , resource resource NOT NULL
  , allowed_actions action[]
  , PRIMARY KEY (role_id, resource)
  , CONSTRAINT allowed_actions_use
    CHECK(to_jsonb(array_to_json(allowed_actions))
          <@ (resource_actions() -> resource::text) IS TRUE)
  );

DROP SEQUENCE IF EXISTS agent_gid_seq CASCADE;
CREATE SEQUENCE agent_gid_seq;

DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users
  ( user_id SERIAL CONSTRAINT upk PRIMARY KEY
  , agent_gid bigint UNIQUE NOT NULL DEFAULT nextval('agent_gid_seq')
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
  , subject TEXT UNIQUE NOT NULL
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

INSERT INTO roles (name, created_at, updated_at, status) VALUES
    ('player', now(), now(), 'role_active')
  , ('wizard', now(), now(), 'role_active')
  , ('admin', now(), now(), 'role_active');

INSERT INTO role_permissions (role_id, resource, allowed_actions)
  SELECT role_id, 'dsl', ARRAY['create']::action[]
    FROM roles WHERE name = 'wizard';
