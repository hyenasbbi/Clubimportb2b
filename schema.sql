-- =====================================================================
-- CLUB IMPORTB2B — ESQUEMA V2
-- Supabase / PostgreSQL
--
-- Esta versión actualiza una instalación V1 existente sin borrar usuarios,
-- clientes ni historial. El sistema deja de usar referidos y créditos como
-- mecánica de fidelización. La regla central pasa a ser:
--
--   1 punto = 1 compra + 1 historia etiquetando a IMPORTB2B, ya verificada.
--
-- IMPORTANTE:
-- - El alta inicial del cliente NO suma un punto.
-- - El administrador solo registra una acción cuando ya tiene la prueba.
-- - No existe estado "historia pendiente" en esta versión.
-- - Club IMPORTB2B exige además una compra >= ARS 30.000.
-- - Los puntos son acumulativos y NO se descuentan al entregar premios.
-- =====================================================================

create extension if not exists pgcrypto;

create sequence if not exists public.client_code_seq start with 1 increment by 1;

-- ---------------------------------------------------------------------
-- TABLAS BASE
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  client_code text not null unique,
  access_token text not null unique,
  full_name text not null,
  phone text,
  instagram_username text,
  joined_at date not null default current_date,
  purchase_count integer not null default 0,
  instagram_story_count integer not null default 0,
  referral_count integer not null default 0,
  credit_balance integer not null default 0,
  is_active boolean not null default true,
  internal_notes text,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Columnas V2. Se agregan sin destruir instalaciones anteriores.
alter table public.clients add column if not exists club_type text;
alter table public.clients add column if not exists points integer;

update public.clients
set club_type = 'importb2b'
where club_type is null or trim(club_type) = '';

update public.clients
set points = 0
where points is null;

alter table public.clients alter column club_type set default 'importb2b';
alter table public.clients alter column club_type set not null;
alter table public.clients alter column points set default 0;
alter table public.clients alter column points set not null;

alter table public.clients drop constraint if exists clients_club_type_check;
alter table public.clients add constraint clients_club_type_check
  check (club_type in ('vapers', 'jerseys', 'perfumes', 'importb2b'));

alter table public.clients drop constraint if exists clients_points_check;
alter table public.clients add constraint clients_points_check check (points >= 0);

create table if not exists public.client_events (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  event_type text not null,
  description text not null,
  credit_amount integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Ampliamos los tipos de evento y mantenemos los tipos antiguos para que
-- el historial de la beta siga siendo legible.
alter table public.client_events drop constraint if exists client_events_event_type_check;
alter table public.client_events add constraint client_events_event_type_check
  check (event_type in (
    'client_created',
    'client_updated',
    'verified_purchase_story',
    'reward_unlocked',
    'reward_delivered',
    'status_change',
    'other',
    'purchase',
    'instagram_story',
    'referral',
    'manual_adjustment',
    'reward_redemption',
    'reward_reversal'
  ));

-- Una fila representa UNA compra + historia ya verificadas.
create table if not exists public.club_actions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  club_type text not null check (club_type in ('vapers', 'jerseys', 'perfumes', 'importb2b')),
  purchase_amount numeric(12,2),
  observation text,
  point_value integer not null default 1 check (point_value = 1),
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Reglas de premios. Para Vapers, milestone=3 + recurring_every=3 significa
-- que se desbloquea otro Vaper a 3, 6, 9, 12, 15... puntos.
create table if not exists public.club_reward_rules (
  id uuid primary key default gen_random_uuid(),
  club_type text not null check (club_type in ('vapers', 'jerseys', 'perfumes', 'importb2b')),
  milestone integer not null check (milestone > 0),
  reward_name text not null,
  reward_description text not null,
  recurring_every integer check (recurring_every is null or recurring_every > 0),
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_type, milestone)
);

create table if not exists public.reward_claims (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  club_type text not null check (club_type in ('vapers', 'jerseys', 'perfumes', 'importb2b')),
  milestone integer not null check (milestone > 0),
  reward_name text not null,
  status text not null default 'pending' check (status in ('pending', 'delivered')),
  notes text,
  unlocked_at timestamptz not null default now(),
  delivered_at timestamptz,
  delivered_by uuid references public.admins(id) on delete set null,
  unique (client_id, club_type, milestone)
);

-- Tablas V1: se conservan para no destruir información anterior.
create table if not exists public.credit_movements (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  client_event_id uuid references public.client_events(id) on delete set null,
  action_type text not null,
  amount integer not null,
  reason text not null,
  balance_after integer not null,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null,
  credits_required integer not null default 1,
  stock integer,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  reward_id uuid references public.rewards(id) on delete set null,
  client_event_id uuid references public.client_events(id) on delete set null,
  credits_spent integer not null default 0,
  status text not null default 'pending',
  notes text,
  redeemed_by uuid references public.admins(id) on delete set null,
  redeemed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- ÍNDICES
-- ---------------------------------------------------------------------
create index if not exists clients_full_name_lower_idx on public.clients (lower(full_name));
create index if not exists clients_phone_idx on public.clients (phone);
create index if not exists clients_instagram_lower_idx on public.clients (lower(instagram_username));
create index if not exists clients_club_type_idx on public.clients (club_type);
create index if not exists clients_points_idx on public.clients (points desc);
create index if not exists clients_active_idx on public.clients (is_active);
create index if not exists client_events_client_date_idx on public.client_events (client_id, created_at desc);
create index if not exists club_actions_client_date_idx on public.club_actions (client_id, created_at desc);
create index if not exists club_actions_club_idx on public.club_actions (club_type, created_at desc);
create index if not exists reward_claims_client_idx on public.reward_claims (client_id, unlocked_at desc);
create index if not exists reward_claims_status_idx on public.reward_claims (status, unlocked_at desc);
create index if not exists club_reward_rules_club_idx on public.club_reward_rules (club_type, display_order, milestone);

-- ---------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.admins a
    where a.id = check_user and a.is_active = true
  );
$$;

create or replace function public.generate_client_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  return 'IMP-' || lpad(nextval('public.client_code_seq')::text, 6, '0');
end;
$$;

-- No usa gen_random_bytes(): genera un token de 64 caracteres con UUIDs.
create or replace function public.generate_client_token()
returns text
language sql
volatile
security definer
set search_path = public
as $$
  select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
$$;

create or replace function public.normalize_instagram_username(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  value text;
begin
  value := trim(coalesce(p_value, ''));
  if value = '' then return null; end if;

  value := regexp_replace(value, '^https?://(www\.)?instagram\.com/', '', 'i');
  value := regexp_replace(value, '^www\.instagram\.com/', '', 'i');
  value := trim(leading '@' from value);
  value := split_part(value, '?', 1);
  value := split_part(value, '#', 1);
  value := split_part(value, '/', 1);
  value := trim(value);

  return nullif(value, '');
end;
$$;

create or replace function public.club_display_name(p_club_type text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_club_type
    when 'vapers' then 'Club Vapers'
    when 'jerseys' then 'Club Jerseys'
    when 'perfumes' then 'Club Perfumes'
    when 'importb2b' then 'Club IMPORTB2B'
    else 'Club IMPORTB2B'
  end;
$$;

create or replace function public.prepare_client_insert()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.client_code is null or trim(new.client_code) = '' then
    new.client_code := public.generate_client_code();
  end if;

  if new.access_token is null or trim(new.access_token) = '' then
    new.access_token := public.generate_client_token();
  end if;

  if new.created_by is null then
    new.created_by := auth.uid();
  end if;

  new.full_name := trim(new.full_name);
  new.phone := nullif(trim(coalesce(new.phone, '')), '');
  new.instagram_username := public.normalize_instagram_username(new.instagram_username);
  new.internal_notes := nullif(trim(coalesce(new.internal_notes, '')), '');
  new.club_type := lower(trim(coalesce(new.club_type, 'importb2b')));
  new.points := coalesce(new.points, 0);

  return new;
end;
$$;

-- Normaliza Instagram ya guardados en la beta.
update public.clients
set instagram_username = public.normalize_instagram_username(instagram_username)
where instagram_username is not null;

-- ---------------------------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------------------------
drop trigger if exists clients_prepare_insert on public.clients;
create trigger clients_prepare_insert
before insert on public.clients
for each row execute function public.prepare_client_insert();

drop trigger if exists admins_set_updated_at on public.admins;
create trigger admins_set_updated_at
before update on public.admins
for each row execute function public.set_updated_at();

drop trigger if exists clients_set_updated_at on public.clients;
create trigger clients_set_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

drop trigger if exists club_reward_rules_set_updated_at on public.club_reward_rules;
create trigger club_reward_rules_set_updated_at
before update on public.club_reward_rules
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- REGLAS DE PREMIOS
-- ---------------------------------------------------------------------
insert into public.club_reward_rules
  (club_type, milestone, reward_name, reward_description, recurring_every, display_order, is_active)
values
  ('vapers', 3, 'Vaper de regalo', 'Un vaper de regalo. Este beneficio vuelve a desbloquearse cada 3 puntos.', 3, 1, true),
  ('jerseys', 4, 'Camiseta versión hincha', 'Camiseta versión hincha de regalo.', null, 1, true),
  ('jerseys', 8, 'Short versión jugador', 'Short versión jugador de regalo.', null, 2, true),
  ('perfumes', 3, 'Perfume Tier C', 'Perfume categoría Tier C de regalo.', null, 1, true),
  ('perfumes', 6, 'Perfume Tier B', 'Perfume categoría Tier B de regalo.', null, 2, true),
  ('perfumes', 10, 'Perfume Tier A', 'Perfume categoría Tier A de regalo.', null, 3, true),
  ('importb2b', 3, 'Cupón 25% OFF', '25% de descuento en cualquier producto de IMPORTB2B.', null, 1, true),
  ('importb2b', 5, 'Artículo Stanley sorpresa', 'Un artículo Stanley seleccionado al azar de regalo.', null, 2, true),
  ('importb2b', 8, 'Mystery Gift IMPORTB2B', 'Un producto sorpresa premium seleccionado por IMPORTB2B.', null, 3, true)
on conflict (club_type, milestone) do update
set reward_name = excluded.reward_name,
    reward_description = excluded.reward_description,
    recurring_every = excluded.recurring_every,
    display_order = excluded.display_order,
    is_active = excluded.is_active;

-- ---------------------------------------------------------------------
-- RPC ADMINISTRATIVAS
-- ---------------------------------------------------------------------
drop function if exists public.admin_create_client(text, text, text, date, text);
drop function if exists public.admin_create_client(text, text, text, date, text, text);
create function public.admin_create_client(
  p_full_name text,
  p_phone text default null,
  p_instagram_username text default null,
  p_joined_at date default current_date,
  p_internal_notes text default null,
  p_club_type text default 'importb2b'
)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_client public.clients;
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) < 2 then
    raise exception 'El nombre del cliente es obligatorio';
  end if;
  if lower(trim(coalesce(p_club_type, ''))) not in ('vapers','jerseys','perfumes','importb2b') then
    raise exception 'Club inválido';
  end if;

  insert into public.clients (
    full_name, phone, instagram_username, joined_at, internal_notes, club_type, points, created_by
  ) values (
    trim(p_full_name),
    nullif(trim(coalesce(p_phone, '')), ''),
    public.normalize_instagram_username(p_instagram_username),
    coalesce(p_joined_at, current_date),
    nullif(trim(coalesce(p_internal_notes, '')), ''),
    lower(trim(p_club_type)),
    0,
    auth.uid()
  ) returning * into created_client;

  insert into public.client_events (client_id, event_type, description, metadata, created_by)
  values (
    created_client.id,
    'client_created',
    'Ingreso al ' || public.club_display_name(created_client.club_type),
    jsonb_build_object('club_type', created_client.club_type, 'points_after', 0),
    auth.uid()
  );

  return created_client;
end;
$$;

drop function if exists public.admin_update_client(uuid, text, text, text, date, text);
drop function if exists public.admin_update_client(uuid, text, text, text, date, text, text);
create function public.admin_update_client(
  p_client_id uuid,
  p_full_name text,
  p_phone text default null,
  p_instagram_username text default null,
  p_joined_at date default current_date,
  p_internal_notes text default null,
  p_club_type text default 'importb2b'
)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_client public.clients;
  updated_client public.clients;
  normalized_club text := lower(trim(coalesce(p_club_type, '')));
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) < 2 then
    raise exception 'El nombre del cliente es obligatorio';
  end if;
  if normalized_club not in ('vapers','jerseys','perfumes','importb2b') then
    raise exception 'Club inválido';
  end if;

  select * into current_client from public.clients where id = p_client_id for update;
  if current_client.id is null then raise exception 'Cliente no encontrado'; end if;

  if current_client.club_type <> normalized_club and current_client.points > 0 then
    raise exception 'No puedes cambiar el club de un cliente que ya tiene puntos registrados';
  end if;

  update public.clients
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      instagram_username = public.normalize_instagram_username(p_instagram_username),
      joined_at = coalesce(p_joined_at, joined_at),
      internal_notes = nullif(trim(coalesce(p_internal_notes, '')), ''),
      club_type = normalized_club
  where id = p_client_id
  returning * into updated_client;

  insert into public.client_events (client_id, event_type, description, metadata, created_by)
  values (
    p_client_id,
    'client_updated',
    'Datos del cliente actualizados',
    jsonb_build_object('club_type', updated_client.club_type),
    auth.uid()
  );

  return updated_client;
end;
$$;

create or replace function public.admin_set_client_status(p_client_id uuid, p_is_active boolean)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  updated_client public.clients;
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  update public.clients set is_active = p_is_active where id = p_client_id returning * into updated_client;
  if updated_client.id is null then raise exception 'Cliente no encontrado'; end if;

  insert into public.client_events (client_id, event_type, description, metadata, created_by)
  values (
    p_client_id,
    'status_change',
    case when p_is_active then 'Cliente reactivado' else 'Cliente desactivado' end,
    jsonb_build_object('is_active', p_is_active),
    auth.uid()
  );

  return updated_client;
end;
$$;

create or replace function public.admin_delete_client(p_client_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
  delete from public.clients where id = p_client_id;
  if not found then raise exception 'Cliente no encontrado'; end if;
  return true;
end;
$$;

-- La única acción que suma puntos.
create or replace function public.admin_register_verified_purchase(
  p_client_id uuid,
  p_purchase_amount numeric default null,
  p_observation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_client public.clients;
  new_points integer;
  action_id uuid;
  event_id uuid;
  reward_name_value text;
  reward_description_value text;
  reward_milestone integer;
  claim_id uuid;
  normalized_observation text := nullif(trim(coalesce(p_observation, '')), '');
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  select * into current_client
  from public.clients
  where id = p_client_id
  for update;

  if current_client.id is null then raise exception 'Cliente no encontrado'; end if;
  if not current_client.is_active then
    raise exception 'El cliente está inactivo. Reactívalo antes de registrar puntos';
  end if;

  if current_client.club_type = 'importb2b' then
    if p_purchase_amount is null or p_purchase_amount < 30000 then
      raise exception 'Club IMPORTB2B requiere una compra mínima de $30.000 para sumar el punto';
    end if;
  end if;

  new_points := current_client.points + 1;

  insert into public.club_actions (
    client_id, club_type, purchase_amount, observation, created_by
  ) values (
    current_client.id,
    current_client.club_type,
    p_purchase_amount,
    normalized_observation,
    auth.uid()
  ) returning id into action_id;

  update public.clients
  set points = new_points,
      purchase_count = purchase_count + 1,
      instagram_story_count = instagram_story_count + 1
  where id = current_client.id;

  insert into public.client_events (
    client_id, event_type, description, metadata, created_by
  ) values (
    current_client.id,
    'verified_purchase_story',
    'Compra + historia etiquetada verificadas',
    jsonb_build_object(
      'club_type', current_client.club_type,
      'point_added', 1,
      'points_after', new_points,
      'purchase_amount', p_purchase_amount,
      'observation', normalized_observation,
      'club_action_id', action_id
    ),
    auth.uid()
  ) returning id into event_id;

  -- Determina si este nuevo punto desbloquea un premio.
  if current_client.club_type = 'vapers' and mod(new_points, 3) = 0 then
    reward_milestone := new_points;
    reward_name_value := 'Vaper de regalo';
    reward_description_value := 'Beneficio recurrente desbloqueado cada 3 puntos.';
  else
    select r.milestone, r.reward_name, r.reward_description
    into reward_milestone, reward_name_value, reward_description_value
    from public.club_reward_rules r
    where r.club_type = current_client.club_type
      and r.is_active = true
      and r.recurring_every is null
      and r.milestone = new_points
    limit 1;
  end if;

  if reward_milestone is not null then
    insert into public.reward_claims (
      client_id, club_type, milestone, reward_name, status
    ) values (
      current_client.id,
      current_client.club_type,
      reward_milestone,
      reward_name_value,
      'pending'
    )
    on conflict (client_id, club_type, milestone) do nothing
    returning id into claim_id;

    if claim_id is not null then
      insert into public.client_events (
        client_id, event_type, description, metadata, created_by
      ) values (
        current_client.id,
        'reward_unlocked',
        'Premio desbloqueado: ' || reward_name_value,
        jsonb_build_object(
          'club_type', current_client.club_type,
          'milestone', reward_milestone,
          'reward_name', reward_name_value,
          'reward_description', reward_description_value,
          'claim_id', claim_id
        ),
        auth.uid()
      );
    end if;
  end if;

  return jsonb_build_object(
    'client_id', current_client.id,
    'points', new_points,
    'action_id', action_id,
    'event_id', event_id,
    'reward_unlocked', reward_name_value,
    'reward_milestone', reward_milestone,
    'claim_id', claim_id
  );
end;
$$;

create or replace function public.admin_update_reward_claim_status(
  p_claim_id uuid,
  p_status text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  claim public.reward_claims;
  previous_status text;
  normalized_status text := lower(trim(coalesce(p_status, '')));
  normalized_notes text := nullif(trim(coalesce(p_notes, '')), '');
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
  if normalized_status not in ('pending', 'delivered') then raise exception 'Estado inválido'; end if;

  select * into claim from public.reward_claims where id = p_claim_id for update;
  if claim.id is null then raise exception 'Premio no encontrado'; end if;
  previous_status := claim.status;

  update public.reward_claims
  set status = normalized_status,
      notes = normalized_notes,
      delivered_at = case when normalized_status = 'delivered' then coalesce(delivered_at, now()) else null end,
      delivered_by = case when normalized_status = 'delivered' then auth.uid() else null end
  where id = p_claim_id
  returning * into claim;

  if normalized_status = 'delivered' and previous_status <> 'delivered' then
    insert into public.client_events (client_id, event_type, description, metadata, created_by)
    values (
      claim.client_id,
      'reward_delivered',
      'Premio entregado: ' || claim.reward_name,
      jsonb_build_object('claim_id', claim.id, 'milestone', claim.milestone, 'reward_name', claim.reward_name),
      auth.uid()
    );
  end if;

  return jsonb_build_object(
    'claim_id', claim.id,
    'status', claim.status,
    'reward_name', claim.reward_name
  );
end;
$$;

-- Ya no se usa el RPC V1 de movimientos con créditos/referidos.
drop function if exists public.admin_register_action(uuid, text, integer, text);

-- ---------------------------------------------------------------------
-- CONSULTAS ADMINISTRATIVAS
-- ---------------------------------------------------------------------
drop function if exists public.admin_search_clients(text);
create function public.admin_search_clients(p_query text default '')
returns table (
  id uuid,
  client_code text,
  access_token text,
  full_name text,
  phone text,
  instagram_username text,
  joined_at date,
  club_type text,
  points integer,
  is_active boolean,
  internal_notes text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  normalized_query text := trim(coalesce(p_query, ''));
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  return query
  select
    c.id, c.client_code, c.access_token, c.full_name, c.phone,
    c.instagram_username, c.joined_at, c.club_type, c.points,
    c.is_active, c.internal_notes, c.created_at, c.updated_at
  from public.clients c
  where normalized_query = ''
     or c.full_name ilike '%' || normalized_query || '%'
     or coalesce(c.phone, '') ilike '%' || normalized_query || '%'
     or coalesce(c.instagram_username, '') ilike '%' || trim(leading '@' from normalized_query) || '%'
     or c.client_code ilike '%' || normalized_query || '%'
  order by c.created_at desc
  limit 500;
end;
$$;

drop function if exists public.admin_get_client_history(uuid);
create function public.admin_get_client_history(p_client_id uuid)
returns table (
  id uuid,
  event_type text,
  description text,
  metadata jsonb,
  created_at timestamptz,
  admin_name text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  return query
  select e.id, e.event_type, e.description, e.metadata, e.created_at, a.full_name
  from public.client_events e
  left join public.admins a on a.id = e.created_by
  where e.client_id = p_client_id
  order by e.created_at desc;
end;
$$;

create or replace function public.admin_get_reward_rules()
returns table (
  id uuid,
  club_type text,
  milestone integer,
  reward_name text,
  reward_description text,
  recurring_every integer,
  display_order integer
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  return query
  select r.id, r.club_type, r.milestone, r.reward_name, r.reward_description,
         r.recurring_every, r.display_order
  from public.club_reward_rules r
  where r.is_active = true
  order by
    case r.club_type when 'vapers' then 1 when 'jerseys' then 2 when 'perfumes' then 3 else 4 end,
    r.display_order,
    r.milestone;
end;
$$;

create or replace function public.admin_get_reward_claims(p_status text default null)
returns table (
  id uuid,
  client_id uuid,
  client_name text,
  client_code text,
  club_type text,
  milestone integer,
  reward_name text,
  status text,
  notes text,
  unlocked_at timestamptz,
  delivered_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  return query
  select rc.id, rc.client_id, c.full_name, c.client_code, rc.club_type,
         rc.milestone, rc.reward_name, rc.status, rc.notes,
         rc.unlocked_at, rc.delivered_at
  from public.reward_claims rc
  join public.clients c on c.id = rc.client_id
  where p_status is null or rc.status = p_status
  order by case when rc.status = 'pending' then 0 else 1 end, rc.unlocked_at desc;
end;
$$;

create or replace function public.admin_get_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'clients_total', (select count(*) from public.clients),
    'clients_active', (select count(*) from public.clients where is_active),
    'valid_actions_total', (select coalesce(sum(points), 0) from public.clients),
    'rewards_unlocked', (select count(*) from public.reward_claims),
    'rewards_pending', (select count(*) from public.reward_claims where status = 'pending'),
    'club_vapers', (select count(*) from public.clients where club_type = 'vapers'),
    'club_jerseys', (select count(*) from public.clients where club_type = 'jerseys'),
    'club_perfumes', (select count(*) from public.clients where club_type = 'perfumes'),
    'club_importb2b', (select count(*) from public.clients where club_type = 'importb2b')
  );
end;
$$;

-- ---------------------------------------------------------------------
-- TARJETA PÚBLICA POR TOKEN
-- ---------------------------------------------------------------------
create or replace function public.get_client_card_by_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  selected_client public.clients;
  club_name_value text;
  next_milestone integer;
  next_reward_name text;
  next_reward_description text;
  progress_percent integer := 0;
  rewards_json jsonb := '[]'::jsonb;
  history_json jsonb := '[]'::jsonb;
  unlocked_count integer := 0;
  delivered_count integer := 0;
  series_count integer;
begin
  if p_token is null or char_length(trim(p_token)) < 32 then return null; end if;

  select * into selected_client
  from public.clients
  where access_token = trim(p_token)
  limit 1;

  if selected_client.id is null then return null; end if;

  club_name_value := public.club_display_name(selected_client.club_type);

  if selected_client.club_type = 'vapers' then
    next_milestone := ((selected_client.points / 3) + 1) * 3;
    next_reward_name := 'Vaper de regalo';
    next_reward_description := 'Se desbloquea un nuevo Vaper cada 3 puntos.';
    series_count := greatest(5, (selected_client.points / 3) + 3);

    select coalesce(jsonb_agg(item order by (item->>'milestone')::integer), '[]'::jsonb)
    into rewards_json
    from (
      select jsonb_build_object(
        'milestone', gs * 3,
        'reward_name', 'Vaper de regalo',
        'description', 'Beneficio recurrente cada 3 puntos.',
        'status', case
          when rc.status = 'delivered' then 'delivered'
          when (gs * 3) <= selected_client.points then 'unlocked'
          else 'locked'
        end,
        'is_unlocked', (gs * 3) <= selected_client.points,
        'is_delivered', rc.status = 'delivered',
        'remaining', greatest((gs * 3) - selected_client.points, 0)
      ) as item
      from generate_series(1, series_count) gs
      left join public.reward_claims rc
        on rc.client_id = selected_client.id
       and rc.club_type = selected_client.club_type
       and rc.milestone = gs * 3
    ) q;
  else
    select r.milestone, r.reward_name, r.reward_description
    into next_milestone, next_reward_name, next_reward_description
    from public.club_reward_rules r
    where r.club_type = selected_client.club_type
      and r.is_active = true
      and r.recurring_every is null
      and r.milestone > selected_client.points
    order by r.milestone
    limit 1;

    select coalesce(jsonb_agg(item order by (item->>'milestone')::integer), '[]'::jsonb)
    into rewards_json
    from (
      select jsonb_build_object(
        'milestone', r.milestone,
        'reward_name', r.reward_name,
        'description', r.reward_description,
        'status', case
          when rc.status = 'delivered' then 'delivered'
          when r.milestone <= selected_client.points then 'unlocked'
          else 'locked'
        end,
        'is_unlocked', r.milestone <= selected_client.points,
        'is_delivered', rc.status = 'delivered',
        'remaining', greatest(r.milestone - selected_client.points, 0)
      ) as item
      from public.club_reward_rules r
      left join public.reward_claims rc
        on rc.client_id = selected_client.id
       and rc.club_type = selected_client.club_type
       and rc.milestone = r.milestone
      where r.club_type = selected_client.club_type
        and r.is_active = true
        and r.recurring_every is null
    ) q;
  end if;

  if next_milestone is null then
    progress_percent := 100;
  else
    progress_percent := least(100, floor((selected_client.points::numeric / next_milestone) * 100)::integer);
  end if;

  select count(*) into unlocked_count
  from public.reward_claims rc
  where rc.client_id = selected_client.id;

  select count(*) into delivered_count
  from public.reward_claims rc
  where rc.client_id = selected_client.id and rc.status = 'delivered';

  select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc), '[]'::jsonb)
  into history_json
  from (
    select e.id, e.event_type, e.description, e.metadata, e.created_at
    from public.client_events e
    where e.client_id = selected_client.id
      and e.event_type in (
        'client_created',
        'verified_purchase_story',
        'reward_unlocked',
        'reward_delivered',
        'status_change',
        'purchase',
        'instagram_story'
      )
    order by e.created_at desc
    limit 50
  ) h;

  return jsonb_build_object(
    'client', jsonb_build_object(
      'full_name', selected_client.full_name,
      'client_code', selected_client.client_code,
      'joined_at', selected_client.joined_at,
      'club_type', selected_client.club_type,
      'club_name', club_name_value,
      'points', selected_client.points,
      'is_active', selected_client.is_active
    ),
    'valid_actions', selected_client.points,
    'unlocked_rewards_count', unlocked_count,
    'delivered_rewards_count', delivered_count,
    'progress_percent', progress_percent,
    'next_reward', case when next_milestone is null then null else jsonb_build_object(
      'milestone', next_milestone,
      'name', next_reward_name,
      'description', next_reward_description,
      'remaining', greatest(next_milestone - selected_client.points, 0)
    ) end,
    'rewards', rewards_json,
    'history', history_json,
    'program_complete', next_milestone is null
  );
end;
$$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.admins enable row level security;
alter table public.clients enable row level security;
alter table public.client_events enable row level security;
alter table public.club_actions enable row level security;
alter table public.club_reward_rules enable row level security;
alter table public.reward_claims enable row level security;
alter table public.credit_movements enable row level security;
alter table public.rewards enable row level security;
alter table public.reward_redemptions enable row level security;

drop policy if exists admins_select_own_or_admin on public.admins;
create policy admins_select_own_or_admin on public.admins
for select to authenticated
using (id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists clients_admin_select on public.clients;
create policy clients_admin_select on public.clients
for select to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists client_events_admin_select on public.client_events;
create policy client_events_admin_select on public.client_events
for select to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists club_actions_admin_select on public.club_actions;
create policy club_actions_admin_select on public.club_actions
for select to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists club_reward_rules_admin_select on public.club_reward_rules;
create policy club_reward_rules_admin_select on public.club_reward_rules
for select to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists reward_claims_admin_select on public.reward_claims;
create policy reward_claims_admin_select on public.reward_claims
for select to authenticated
using (public.is_admin(auth.uid()));

-- ---------------------------------------------------------------------
-- PERMISOS
-- ---------------------------------------------------------------------
revoke all on public.clients from anon;
revoke all on public.client_events from anon;
revoke all on public.club_actions from anon;
revoke all on public.club_reward_rules from anon;
revoke all on public.reward_claims from anon;

revoke all on function public.get_client_card_by_token(text) from public;
grant execute on function public.get_client_card_by_token(text) to anon, authenticated;

grant select on public.admins to authenticated;

grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.admin_create_client(text, text, text, date, text, text) to authenticated;
grant execute on function public.admin_update_client(uuid, text, text, text, date, text, text) to authenticated;
grant execute on function public.admin_set_client_status(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_client(uuid) to authenticated;
grant execute on function public.admin_register_verified_purchase(uuid, numeric, text) to authenticated;
grant execute on function public.admin_update_reward_claim_status(uuid, text, text) to authenticated;
grant execute on function public.admin_search_clients(text) to authenticated;
grant execute on function public.admin_get_client_history(uuid) to authenticated;
grant execute on function public.admin_get_reward_rules() to authenticated;
grant execute on function public.admin_get_reward_claims(text) to authenticated;
grant execute on function public.admin_get_stats() to authenticated;

-- ---------------------------------------------------------------------
-- VERIFICACIÓN FINAL
-- ---------------------------------------------------------------------
select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='clients' and column_name='club_type') as club_type_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='clients' and column_name='points') as points_ok,
  to_regclass('public.club_actions') is not null as club_actions_ok,
  to_regclass('public.club_reward_rules') is not null as reward_rules_ok,
  to_regclass('public.reward_claims') is not null as reward_claims_ok;
