-- ISOLATED GitHub Actions PostgreSQL fixture ONLY. Fake extra Auth sessions.
-- auth.sessions was already created in device_fixture.sql.
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
('aaaaaaaa-3333-4333-8333-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()-interval '1 day'),
('aaaaaaaa-4444-4444-8444-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL);
