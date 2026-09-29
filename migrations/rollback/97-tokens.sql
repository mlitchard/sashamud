DROP TABLE IF EXISTS tokens CASCADE;
CREATE TABLE tokens
  ( token_digest bytea CONSTRAINT tpk PRIMARY KEY
  , user_id INT NOT NULL REFERENCES users(user_id)
  , created timestamp with time zone NOT NULL
  , expires_at timestamp with time zone NOT NULL
  );
