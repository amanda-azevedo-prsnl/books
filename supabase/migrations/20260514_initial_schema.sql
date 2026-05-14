-- Enable UUID extension
create extension if not exists "uuid-ossp" schema extensions;

-- ─────────────────────────────────────────
-- PROFILES
-- ─────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text unique not null,
  full_name   text,
  avatar_url  text,
  bio         text,
  created_at  timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Profiles are viewable by everyone" on public.profiles
  for select using (true);

create policy "Users can update their own profile" on public.profiles
  for update using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', '')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────
-- BOOKS
-- ─────────────────────────────────────────
create table public.books (
  id            uuid primary key default gen_random_uuid(),
  google_books_id text unique,
  title         text not null,
  author        text,
  cover_url     text,
  description   text,
  page_count    int,
  published_at  date,
  genres        text[],
  created_at    timestamptz default now()
);

alter table public.books enable row level security;

create policy "Books are viewable by everyone" on public.books
  for select using (true);

create policy "Authenticated users can insert books" on public.books
  for insert with check (auth.role() = 'authenticated');

-- ─────────────────────────────────────────
-- USER_BOOKS (estante)
-- ─────────────────────────────────────────
create type reading_status as enum ('want_to_read', 'reading', 'read', 'abandoned');

create table public.user_books (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  book_id     uuid not null references public.books(id) on delete cascade,
  status      reading_status not null default 'want_to_read',
  progress    int default 0 check (progress >= 0 and progress <= 100),
  rating      int check (rating >= 1 and rating <= 5),
  started_at  date,
  finished_at date,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (user_id, book_id)
);

alter table public.user_books enable row level security;

create policy "User books are viewable by everyone" on public.user_books
  for select using (true);

create policy "Users can manage their own books" on public.user_books
  for all using (auth.uid() = user_id);

-- ─────────────────────────────────────────
-- REVIEWS
-- ─────────────────────────────────────────
create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  book_id     uuid not null references public.books(id) on delete cascade,
  body        text not null,
  rating      int check (rating >= 1 and rating <= 5),
  has_spoiler boolean default false,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (user_id, book_id)
);

alter table public.reviews enable row level security;

create policy "Reviews are viewable by everyone" on public.reviews
  for select using (true);

create policy "Users can manage their own reviews" on public.reviews
  for all using (auth.uid() = user_id);

-- ─────────────────────────────────────────
-- FOLLOWS
-- ─────────────────────────────────────────
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz default now(),
  primary key (follower_id, following_id),
  check (follower_id != following_id)
);

alter table public.follows enable row level security;

create policy "Follows are viewable by everyone" on public.follows
  for select using (true);

create policy "Users can manage their own follows" on public.follows
  for all using (auth.uid() = follower_id);

-- ─────────────────────────────────────────
-- ACTIVITIES (feed)
-- ─────────────────────────────────────────
create type activity_type as enum (
  'added_book',
  'started_reading',
  'updated_progress',
  'finished_book',
  'wrote_review',
  'gave_rating'
);

create table public.activities (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  activity_type activity_type not null,
  book_id       uuid references public.books(id) on delete cascade,
  review_id     uuid references public.reviews(id) on delete cascade,
  metadata      jsonb default '{}',
  created_at    timestamptz default now()
);

alter table public.activities enable row level security;

create policy "Activities are viewable by everyone" on public.activities
  for select using (true);

create policy "Users can manage their own activities" on public.activities
  for all using (auth.uid() = user_id);

-- Index para feed por usuário
create index activities_user_id_idx on public.activities(user_id, created_at desc);
create index activities_created_at_idx on public.activities(created_at desc);
