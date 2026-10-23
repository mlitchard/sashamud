CREATE TABLE dsl_submission
  ( id           bigserial   PRIMARY KEY
  , user_id      integer     NOT NULL REFERENCES users(user_id)
  , source       text        NOT NULL
  , submitted_at timestamptz NOT NULL DEFAULT now()
  );
