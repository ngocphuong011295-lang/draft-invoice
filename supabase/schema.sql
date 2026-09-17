-- =====================================================================
--  Hóa đơn nháp iPOS — Supabase schema
--  Chạy toàn bộ file này 1 lần trong Supabase Dashboard → SQL Editor → Run.
--  Tạo: bảng danh mục (products = hàng hóa, customers = đối tượng), nháp (drafts),
--       hồ sơ người dùng (profiles), hàm quản trị tài khoản, RLS,
--       và tài khoản admin mặc định (admin / 123).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. HỒ SƠ NGƯỜI DÙNG (gắn với auth.users)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text,
  role         text not null default 'user' check (role in ('admin', 'user')),
  created_at   timestamptz not null default now()
);

-- Người dùng tạo bằng Dashboard (Authentication → Add user) cũng tự có profile
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name, role)
  values (new.id, split_part(new.email, '@', 1), coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)), 'user')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------------------------------------------------------------------
-- 2. DANH MỤC & NHÁP
-- ---------------------------------------------------------------------
create table if not exists public.products (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null,
  name       text not null,
  unit       text not null default '',
  rate       text not null default '8',
  price      numeric not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,           -- mã đối tượng (khóa)
  tax_code     text not null default '',    -- MST: có thể trống hoặc trùng
  company_name text not null default '',
  person_name  text not null default '',
  address      text not null default '',
  id_card      text not null default '',
  passport     text not null default '',
  budget_code  text not null default '',
  bank_account text not null default '',
  updated_at   timestamptz not null default now()
);

create table if not exists public.drafts (
  id            uuid primary key default gen_random_uuid(),
  contract_code text not null default '',
  customer_name text not null default '',
  total         numeric not null default 0,
  data          jsonb not null,
  created_by    uuid references auth.users(id) on delete set null,
  updated_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. RLS: chỉ người đã đăng nhập mới đọc/ghi
-- ---------------------------------------------------------------------
alter table public.profiles  enable row level security;
alter table public.products  enable row level security;
alter table public.customers enable row level security;
alter table public.drafts    enable row level security;

drop policy if exists "profiles read"   on public.profiles;
create policy "profiles read"   on public.profiles  for select to authenticated using (true);

drop policy if exists "products all"   on public.products;
create policy "products all"   on public.products  for all to authenticated using (true) with check (true);
drop policy if exists "customers all"  on public.customers;
create policy "customers all"  on public.customers for all to authenticated using (true) with check (true);
drop policy if exists "drafts all"     on public.drafts;
create policy "drafts all"     on public.drafts    for all to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------
-- 4. QUẢN LÝ TÀI KHOẢN (chỉ admin gọi được, qua RPC)
--    Đăng nhập bằng "tên đăng nhập"; email nội bộ = <username>@ipos.local
-- ---------------------------------------------------------------------
create or replace function public._create_user_internal(p_username text, p_password text, p_display_name text, p_role text)
returns uuid language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_username)) || '@ipos.local';
begin
  if p_username is null or trim(p_username) = '' then raise exception 'Thiếu tên đăng nhập'; end if;
  if p_password is null or p_password = '' then raise exception 'Thiếu mật khẩu'; end if;
  if exists (select 1 from auth.users where email = v_email) then raise exception 'Tên đăng nhập "%" đã tồn tại', p_username; end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token,
    is_sso_user, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', coalesce(p_display_name, p_username)), now(), now(),
    '', '', '', '', '', '', '', '', false, false
  );

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());

  insert into public.profiles (id, username, display_name, role)
  values (v_id, lower(trim(p_username)), coalesce(p_display_name, p_username), coalesce(p_role, 'user'))
  on conflict (id) do update set username = excluded.username, display_name = excluded.display_name, role = excluded.role;

  return v_id;
end $$;
revoke all on function public._create_user_internal(text, text, text, text) from public, anon, authenticated;

create or replace function public.admin_create_user(p_username text, p_password text, p_display_name text default null, p_role text default 'user')
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Chỉ admin mới được tạo tài khoản'; end if;
  if p_role not in ('admin', 'user') then raise exception 'Vai trò không hợp lệ'; end if;
  return public._create_user_internal(p_username, p_password, p_display_name, p_role);
end $$;

create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if not public.is_admin() then raise exception 'Chỉ admin mới được đặt lại mật khẩu'; end if;
  if p_password is null or p_password = '' then raise exception 'Thiếu mật khẩu'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = p_user;
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Chỉ admin mới được đổi vai trò'; end if;
  if p_role not in ('admin', 'user') then raise exception 'Vai trò không hợp lệ'; end if;
  if p_user = auth.uid() and p_role <> 'admin' then raise exception 'Không thể tự bỏ quyền admin của chính mình'; end if;
  update public.profiles set role = p_role where id = p_user;
end $$;

create or replace function public.admin_update_display_name(p_user uuid, p_display_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Chỉ admin mới được sửa'; end if;
  update public.profiles set display_name = p_display_name where id = p_user;
end $$;

create or replace function public.admin_delete_user(p_user uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Chỉ admin mới được xóa tài khoản'; end if;
  if p_user = auth.uid() then raise exception 'Không thể tự xóa tài khoản đang đăng nhập'; end if;
  delete from auth.users where id = p_user;   -- cascade: identities, profiles
end $$;

create or replace function public.admin_list_users()
returns table (id uuid, username text, display_name text, role text, created_at timestamptz, last_sign_in_at timestamptz)
language sql security definer set search_path = public, auth as $$
  select p.id, p.username, p.display_name, p.role, p.created_at, u.last_sign_in_at
  from public.profiles p join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.role, p.username;
$$;

-- Hồ sơ của chính mình (dùng sau khi đăng nhập)
create or replace function public.my_profile()
returns table (id uuid, username text, display_name text, role text)
language sql stable security definer set search_path = public as $$
  select id, username, display_name, role from public.profiles where id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 5. TÀI KHOẢN ADMIN MẶC ĐỊNH:  admin / 123   (đổi mật khẩu ngay sau khi vào)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from auth.users where email = 'admin@ipos.local') then
    perform public._create_user_internal('admin', '123', 'Quản trị', 'admin');
  end if;
end $$;

-- (Danh mục hàng hóa / đối tượng được nhập từ file Excel qua app hoặc CLI, không seed ở đây)
