DROP TABLE IF EXISTS slm CASCADE;
CREATE TABLE slm
  ( slm_id SERIAL CONSTRAINT slmpk PRIMARY KEY
  , name TEXT UNIQUE NOT NULL
  );

DROP TABLE IF EXISTS repair_failures CASCADE;
CREATE TABLE repair_failures
  ( failure_id SERIAL CONSTRAINT rfpk PRIMARY KEY
  , scene TEXT NOT NULL
  , actor INT NOT NULL REFERENCES users(user_id)
  , unparsed_sentence TEXT NOT NULL
  , parse_error TEXT NOT NULL
  , attempts TEXT[] NOT NULL
  , attempt_errors TEXT[] NOT NULL
  , slm_id INT NOT NULL REFERENCES slm(slm_id)
  );

DROP TABLE IF EXISTS repair_successes CASCADE;
CREATE TABLE repair_successes
  ( success_id SERIAL CONSTRAINT rspk PRIMARY KEY
  , scene TEXT NOT NULL
  , actor INT NOT NULL REFERENCES users(user_id)
  , unparsed_sentence TEXT NOT NULL
  , rewrite TEXT NOT NULL
  , slm_id INT NOT NULL REFERENCES slm(slm_id)
  );

INSERT INTO slm (name) VALUES ('qwen-Qwen3-1.7B-Q8_0'), ('slm-absent');
