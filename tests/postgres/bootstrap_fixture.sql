-- ISOLATED GitHub Actions PostgreSQL fixture ONLY. Fake Auth sessions.
-- This intentionally simulates only the required auth.sessions columns.
CREATE TABLE auth.sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  not_after timestamptz
);
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL),
('bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',NULL),
('aaaaaaaa-3333-4333-8333-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()-interval '1 day'),
('aaaaaaaa-4444-4444-8444-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL);
