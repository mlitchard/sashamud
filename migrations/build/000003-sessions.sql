ALTER TABLE tokens ADD COLUMN expires_at timestamp with time zone;
UPDATE tokens SET expires_at = created + interval '1 day';
ALTER TABLE tokens ALTER COLUMN expires_at SET NOT NULL;

CREATE TABLE user_logs
  ( user_id integer NOT NULL
  , path text  NOT NULL
  , timet timestamp with time zone NOT NULL
  );
