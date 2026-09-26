-- Run this migration before inviting either person. Public sign-ups must be disabled
-- in Supabase Auth; then invite exactly the two email addresses you control.
create extension if not exists pgcrypto;

create table if not exists public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our Little World',
  start_date date not null default current_date,
  created_at timestamptz not null default now()
);
create table if not exists public.space_members (
  space_id uuid not null references public.spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'My person',
  joined_at timestamptz not null default now(),
  primary key(space_id,user_id)
);
create or replace function public.enforce_two_members()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
 perform pg_advisory_xact_lock(hashtext(new.space_id::text));
 if (select count(*) from public.space_members where space_id=new.space_id)>=2 then
   raise exception 'This relationship space is limited to exactly two members';
 end if;
 return new;
end $$;
create trigger only_two_members before insert on public.space_members for each row execute function public.enforce_two_members();
create or replace function public.is_space_member(target uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.space_members m where m.space_id=target and m.user_id=auth.uid()) $$;
revoke all on function public.is_space_member(uuid) from public;
grant execute on function public.is_space_member(uuid) to authenticated;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  space_id uuid not null references public.spaces(id) on delete cascade,
  nickname text not null default '', birthday date, favorite_color text, favorite_song text,
  favorite_food text, quote text, love_language text, status text, updated_at timestamptz default now()
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(), space_id uuid not null references public.spaces(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade, body text not null default '',
  media_path text, media_type text, reply_to uuid references public.messages(id) on delete set null,
  edited_at timestamptz, read_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.message_receipts (
 message_id uuid not null references public.messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null default now(),
 primary key(message_id,user_id)
);
create index if not exists messages_space_created on public.messages(space_id,created_at);
create table if not exists public.message_reactions (
 id uuid primary key default gen_random_uuid(), message_id uuid not null references public.messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, emoji text not null,
 unique(message_id,user_id,emoji)
);
create table if not exists public.message_flags (
 message_id uuid not null references public.messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 pinned boolean not null default false, starred boolean not null default false,
 primary key(message_id,user_id)
);
-- Typed JSON records power memories, milestones, songs, letters, journal, bucket list,
-- date ideas, games, moods, map pins, compliments, and notifications.
create table if not exists public.records (
 id uuid primary key default gen_random_uuid(), space_id uuid not null references public.spaces(id) on delete cascade,
 kind text not null check(kind in ('memory','milestone','song','letter','journal','bucket','date','game','mood','location','compliment','notification','question')),
 created_by uuid not null references auth.users(id) on delete cascade,
 title text not null default '', body text not null default '', data jsonb not null default '{}'::jsonb,
 media_path text, visible_at timestamptz default now(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists records_space_kind on public.records(space_id,kind,created_at desc);
create table if not exists public.record_reactions (
 id uuid primary key default gen_random_uuid(), record_id uuid not null references public.records(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, emoji text not null default '❤️',
 created_at timestamptz not null default now(), unique(record_id,user_id,emoji)
);
create table if not exists public.daily_answers (
 id uuid primary key default gen_random_uuid(), space_id uuid not null references public.spaces(id) on delete cascade,
 question_date date not null default current_date, user_id uuid not null references auth.users(id) on delete cascade,
 answer text not null, created_at timestamptz not null default now(), unique(space_id,question_date,user_id)
);
create or replace function public.can_reveal_daily_answers(target uuid, target_date date)
returns boolean language sql stable security definer set search_path=public
as $$ select count(*)>=2 from public.daily_answers where space_id=target and question_date=target_date $$;
revoke all on function public.can_reveal_daily_answers(uuid,date) from public;
grant execute on function public.can_reveal_daily_answers(uuid,date) to authenticated;

alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
alter table public.message_receipts enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_flags enable row level security;
alter table public.record_reactions enable row level security;
alter table public.records enable row level security;
alter table public.daily_answers enable row level security;

create policy "members read their space" on public.spaces for select to authenticated using(public.is_space_member(id));
create policy "pair members update their space" on public.spaces for update to authenticated using(public.is_space_member(id)) with check(public.is_space_member(id));
create policy "members see each other" on public.space_members for select to authenticated using(public.is_space_member(space_id));
create policy "members manage profiles" on public.profiles for all to authenticated using(public.is_space_member(space_id)) with check(public.is_space_member(space_id) and user_id=auth.uid());
create policy "members read messages" on public.messages for select to authenticated using(public.is_space_member(space_id));
create policy "members send own messages" on public.messages for insert to authenticated with check(public.is_space_member(space_id) and sender_id=auth.uid());
create policy "authors edit messages" on public.messages for update to authenticated using(sender_id=auth.uid() and public.is_space_member(space_id)) with check(sender_id=auth.uid() and public.is_space_member(space_id));
create policy "authors delete messages" on public.messages for delete to authenticated using(sender_id=auth.uid() and public.is_space_member(space_id));
create policy "pair members see receipts" on public.message_receipts for select to authenticated using(exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id)));
create policy "users create their own receipts" on public.message_receipts for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id)));
create policy "users update their own receipts" on public.message_receipts for update to authenticated using(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id))) with check(user_id=auth.uid());
create policy "members read reactions" on public.message_reactions for select to authenticated using(exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id)));
create policy "members manage own reactions" on public.message_reactions for all to authenticated using(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id))) with check(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id)));
create policy "members manage own flags" on public.message_flags for all to authenticated using(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id))) with check(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_space_member(m.space_id)));
create policy "members read available records" on public.records for select to authenticated using(public.is_space_member(space_id) and (created_by=auth.uid() or visible_at<=now()));
create policy "members create records" on public.records for insert to authenticated with check(public.is_space_member(space_id) and created_by=auth.uid());
create policy "authors and pair plans edit records" on public.records for update to authenticated using(public.is_space_member(space_id) and (created_by=auth.uid() or kind='bucket')) with check(public.is_space_member(space_id) and (created_by=auth.uid() or kind='bucket'));
create policy "authors delete their records" on public.records for delete to authenticated using(public.is_space_member(space_id) and created_by=auth.uid());
create policy "members read record reactions" on public.record_reactions for select to authenticated using(exists(select 1 from public.records r where r.id=record_id and public.is_space_member(r.space_id)));
create policy "members manage their record reactions" on public.record_reactions for all to authenticated using(user_id=auth.uid() and exists(select 1 from public.records r where r.id=record_id and public.is_space_member(r.space_id))) with check(user_id=auth.uid() and exists(select 1 from public.records r where r.id=record_id and public.is_space_member(r.space_id)));
create policy "answer privately until both answer" on public.daily_answers for select to authenticated using(
 user_id=auth.uid() or (public.is_space_member(space_id) and public.can_reveal_daily_answers(space_id,question_date))
);
create policy "write own daily answer" on public.daily_answers for insert to authenticated with check(public.is_space_member(space_id) and user_id=auth.uid());
create policy "edit own daily answer" on public.daily_answers for update to authenticated using(user_id=auth.uid() and public.is_space_member(space_id)) with check(user_id=auth.uid());

revoke all on public.spaces,public.space_members,public.profiles,public.messages,public.message_receipts,public.message_reactions,public.message_flags,public.records,public.record_reactions,public.daily_answers from anon;
grant select on public.spaces,public.space_members,public.profiles,public.messages,public.message_receipts,public.message_reactions,public.message_flags,public.records,public.record_reactions,public.daily_answers to authenticated;
grant update on public.spaces to authenticated;
grant insert,update,delete on public.profiles,public.messages,public.message_receipts,public.message_reactions,public.message_flags,public.records,public.record_reactions,public.daily_answers to authenticated;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_receipts;
alter publication supabase_realtime add table public.message_reactions;
alter publication supabase_realtime add table public.records;
alter publication supabase_realtime add table public.record_reactions;

-- Realtime channels carry private presence and typing events for paired members only.
create policy "pair members receive private realtime" on realtime.messages for select to authenticated
using ((realtime.topic() like 'space:%' or realtime.topic() like 'space-presence:%') and public.is_space_member(split_part(realtime.topic(),':',2)::uuid));
create policy "pair members send private realtime" on realtime.messages for insert to authenticated
with check ((realtime.topic() like 'space:%' or realtime.topic() like 'space-presence:%') and public.is_space_member(split_part(realtime.topic(),':',2)::uuid));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('couple-private','couple-private',false,52428800,array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/webm','video/quicktime','audio/mpeg','audio/mp4','audio/webm','audio/ogg','audio/wav'])
on conflict(id) do update set public=false;
create policy "space members access private media" on storage.objects for select to authenticated using(bucket_id='couple-private' and public.is_space_member((storage.foldername(name))[1]::uuid));
create policy "space members upload private media" on storage.objects for insert to authenticated with check(bucket_id='couple-private' and public.is_space_member((storage.foldername(name))[1]::uuid));
create policy "space members update private media" on storage.objects for update to authenticated using(bucket_id='couple-private' and public.is_space_member((storage.foldername(name))[1]::uuid)) with check(bucket_id='couple-private' and public.is_space_member((storage.foldername(name))[1]::uuid));
create policy "space members delete private media" on storage.objects for delete to authenticated using(bucket_id='couple-private' and public.is_space_member((storage.foldername(name))[1]::uuid));

-- Secure bootstrap: after disabling public sign-ups and inviting both emails, run
-- the separate bootstrap SQL shown in README with the two Auth user UUIDs.

