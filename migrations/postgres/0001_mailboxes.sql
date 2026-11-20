-- MicrosoftMCP schema for PostgreSQL. Times are UTC (timestamptz).

CREATE TABLE microsoftmcp_mailboxes (
  user_id       varchar(64)  NOT NULL,
  slug          varchar(32)  NOT NULL,
  display_name  text         NOT NULL,
  address       text         NOT NULL,
  account_key   text         NOT NULL,
  kind          varchar(16)  NOT NULL CHECK (kind IN ('own', 'shared')),
  created_at    timestamptz  NOT NULL,
  PRIMARY KEY (user_id, slug)
);

CREATE INDEX microsoftmcp_mailboxes_account_key ON microsoftmcp_mailboxes (account_key);
