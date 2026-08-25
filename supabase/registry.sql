-- vibe-registry 中央登記表
-- 跑在一個獨立的 Supabase 專案（不要混進 CRM 的 staging/prod）
-- 在 Supabase Dashboard > SQL Editor 執行一次即可

create table if not exists public.vibe_projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  owner text not null,
  members text[] not null default '{}',
  url text,
  status text not null default 'active'
    check (status in ('active', 'paused', 'done', 'stale')),
  latest_update text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 既有表補欄位（冪等；多人協作同一專案時的其他成員）
alter table public.vibe_projects
  add column if not exists members text[] not null default '{}';

-- 既有表補欄位（冪等；專案部署後的成品網址，供沿用）
alter table public.vibe_projects
  add column if not exists url text;

-- updated_at 自動更新
create or replace function public.vibe_projects_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_vibe_projects_touch on public.vibe_projects;
create trigger trg_vibe_projects_touch
  before update on public.vibe_projects
  for each row execute function public.vibe_projects_touch();

-- RLS：啟用但「零政策」= anon / authenticated 完全不可直接碰這張表。
-- 唯一存取路徑是 Edge Function `vibe-registry`（service_role 繞過 RLS）。
-- 發給使用者的 REGISTRY_TOKEN 只對函式有效，與資料庫憑證完全脫鉤——
-- 本專案 DB 內還有其他資料，絕不能把 anon key 發出去。
alter table public.vibe_projects enable row level security;

drop policy if exists vibe_projects_select on public.vibe_projects;
drop policy if exists vibe_projects_insert on public.vibe_projects;
drop policy if exists vibe_projects_update on public.vibe_projects;

-- （選配）自動標記停滯：active 超過 14 天沒更新 → stale
-- 需要先在 Dashboard > Database > Extensions 啟用 pg_cron，再執行：
-- select cron.schedule('vibe-registry-stale-sweep', '0 1 * * *', $$
--   update public.vibe_projects
--   set status = 'stale'
--   where status = 'active' and updated_at < now() - interval '14 days'
-- $$);
