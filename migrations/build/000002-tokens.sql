DROP TABLE IF EXISTS tokens CASCADE;
CREATE TABLE tokens
  ( token   TEXT CONSTRAINT tpk PRIMARY KEY
  , hash    bytea NOT NULL
  , user_id INT UNIQUE NOT NULL REFERENCES users(user_id)
  , created timestamp with time zone NOT NULL
  );
