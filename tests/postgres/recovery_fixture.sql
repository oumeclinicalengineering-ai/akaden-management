-- Fictional accounts and Auth sessions; used only by temporary PostgreSQL.
INSERT INTO auth.users(id)
VALUES('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
INSERT INTO public.profiles(user_id,display_name,role,active)
VALUES('cccccccc-cccc-4ccc-8ccc-cccccccccccc','試験管理者2','admin',true);
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
  ('aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL),
  ('aaaaaaaa-7777-4777-8777-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL),
  ('cccccccc-2222-4222-8222-cccccccccccc','cccccccc-cccc-4ccc-8ccc-cccccccccccc',NULL);
