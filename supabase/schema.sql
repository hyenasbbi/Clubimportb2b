-- CLUB IMPORTB2B — schema.sql RESET DEFINITIVO
-- Ejecutar el archivo COMPLETO desde la primera hasta la última línea.
-- Elimina y recrea el esquema public; NO elimina usuarios de Authentication.
-- No usa gen_random_bytes().


-- Reinicio total del esquema público para evitar restos de versiones incompatibles.
drop schema if exists public cascade;
create schema public authorization postgres;

-- Permisos base requeridos por Supabase.
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
grant create on schema public to postgres, service_role;

create extension if not exists pgcrypto;

create sequence public.client_code_seq start with 1 increment by 1;

create table public.admins (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  client_code text not null unique,
  access_token text not null unique,
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  phone text,
  instagram_username text,
  joined_at date not null default current_date,
  purchase_count integer not null default 0 check (purchase_count >= 0),
  instagram_story_count integer not null default 0 check (instagram_story_count >= 0),
  referral_count integer not null default 0 check (referral_count >= 0),
  credit_balance integer not null default 0 check (credit_balance >= 0),
  is_active boolean not null default true,
  internal_notes text,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.client_events (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  event_type text not null check (event_type in (
    'client_created',
    'client_updated',
    'purchase',
    'instagram_story',
    'referral',
    'manual_adjustment',
    'reward_redemption',
    'reward_reversal',
    'status_change',
    'other'
  )),
  description text not null check (char_length(trim(description)) between 2 and 500),
  credit_amount integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.credit_movements (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  client_event_id uuid references public.client_events(id) on delete set null,
  action_type text not null check (action_type in (
    'purchase',
    'instagram_story',
    'referral',
    'manual_adjustment',
    'reward_redemption',
    'reward_reversal',
    'other'
  )),
  amount integer not null check (amount <> 0),
  reason text not null check (char_length(trim(reason)) between 2 and 500),
  balance_after integer not null check (balance_after >= 0),
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  description text not null check (char_length(trim(description)) between 2 and 500),
  credits_required integer not null check (credits_required > 0),
  stock integer check (stock is null or stock >= 0),
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  reward_id uuid not null references public.rewards(id) on delete restrict,
  client_event_id uuid references public.client_events(id) on delete set null,
  credits_spent integer not null check (credits_spent > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'delivered', 'cancelled')),
  notes text,
  redeemed_by uuid references public.admins(id) on delete set null,
  redeemed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists clients_full_name_lower_idx on public.clients (lower(full_name));
create index if not exists clients_phone_idx on public.clients (phone);
create index if not exists clients_instagram_lower_idx on public.clients (lower(instagram_username));
create index if not exists clients_active_idx on public.clients (is_active);
create index if not exists clients_created_at_idx on public.clients (created_at desc);
create index if not exists client_events_client_date_idx on public.client_events (client_id, created_at desc);
create index if not exists credit_movements_client_date_idx on public.credit_movements (client_id, created_at desc);
create index if not exists rewards_active_order_idx on public.rewards (is_active, display_order, credits_required);
create index if not exists redemptions_client_date_idx on public.reward_redemptions (client_id, redeemed_at desc);
create index if not exists redemptions_status_idx on public.reward_redemptions (status);

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
    where a.id = check_user
      and a.is_active = true
  );
$$;

create or replace function public.generate_client_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  generated_code text;
begin
  generated_code := 'IMP-' || lpad(nextval('public.client_code_seq')::text, 6, '0');
  return generated_code;
end;
$$;

create or replace function public.generate_client_token()
returns text
language sql
volatile
security definer
set search_path = public, pg_catalog
as $$
  select replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
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
  new.instagram_username := nullif(trim(leading '@' from trim(coalesce(new.instagram_username, ''))), '');
  new.internal_notes := nullif(trim(coalesce(new.internal_notes, '')), '');

  return new;
end;
$$;

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

drop trigger if exists rewards_set_updated_at on public.rewards;
create trigger rewards_set_updated_at
before update on public.rewards
for each row execute function public.set_updated_at();

drop trigger if exists redemptions_set_updated_at on public.reward_redemptions;
create trigger redemptions_set_updated_at
before update on public.reward_redemptions
for each row execute function public.set_updated_at();

create or replace function public.admin_create_client(
  p_full_name text,
  p_phone text default null,
  p_instagram_username text default null,
  p_joined_at date default current_date,
  p_internal_notes text default null
)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_client public.clients;
  created_event_id uuid;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  if p_full_name is null or char_length(trim(p_full_name)) < 2 then
    raise exception 'El nombre del cliente es obligatorio';
  end if;

  insert into public.clients (
    full_name,
    phone,
    instagram_username,
    joined_at,
    internal_notes,
    created_by
  ) values (
    trim(p_full_name),
    nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(leading '@' from trim(coalesce(p_instagram_username, ''))), ''),
    coalesce(p_joined_at, current_date),
    nullif(trim(coalesce(p_internal_notes, '')), ''),
    auth.uid()
  )
  returning * into created_client;

  insert into public.client_events (
    client_id,
    event_type,
    description,
    credit_amount,
    created_by
  ) values (
    created_client.id,
    'client_created',
    'Cliente incorporado al Club IMPORTB2B',
    0,
    auth.uid()
  ) returning id into created_event_id;

  return created_client;
end;
$$;

create or replace function public.admin_update_client(
  p_client_id uuid,
  p_full_name text,
  p_phone text default null,
  p_instagram_username text default null,
  p_joined_at date default current_date,
  p_internal_notes text default null
)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  updated_client public.clients;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  if p_full_name is null or char_length(trim(p_full_name)) < 2 then
    raise exception 'El nombre del cliente es obligatorio';
  end if;

  update public.clients
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      instagram_username = nullif(trim(leading '@' from trim(coalesce(p_instagram_username, ''))), ''),
      joined_at = coalesce(p_joined_at, joined_at),
      internal_notes = nullif(trim(coalesce(p_internal_notes, '')), '')
  where id = p_client_id
  returning * into updated_client;

  if updated_client.id is null then
    raise exception 'Cliente no encontrado';
  end if;

  insert into public.client_events (
    client_id,
    event_type,
    description,
    credit_amount,
    created_by
  ) values (
    p_client_id,
    'client_updated',
    'Datos del cliente actualizados',
    0,
    auth.uid()
  );

  return updated_client;
end;
$$;

create or replace function public.admin_set_client_status(
  p_client_id uuid,
  p_is_active boolean
)
returns public.clients
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  updated_client public.clients;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  update public.clients
  set is_active = p_is_active
  where id = p_client_id
  returning * into updated_client;

  if updated_client.id is null then
    raise exception 'Cliente no encontrado';
  end if;

  insert into public.client_events (
    client_id,
    event_type,
    description,
    credit_amount,
    metadata,
    created_by
  ) values (
    p_client_id,
    'status_change',
    case when p_is_active then 'Cliente reactivado' else 'Cliente desactivado' end,
    0,
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
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  delete from public.clients where id = p_client_id;

  if not found then
    raise exception 'Cliente no encontrado';
  end if;

  return true;
end;
$$;

create or replace function public.admin_register_action(
  p_client_id uuid,
  p_action_type text,
  p_credit_amount integer default 0,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_client public.clients;
  new_balance integer;
  event_id uuid;
  normalized_reason text;
  new_purchase_count integer;
  new_story_count integer;
  new_referral_count integer;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  if p_action_type not in ('purchase', 'instagram_story', 'referral', 'manual_adjustment', 'other') then
    raise exception 'Tipo de acción inválido';
  end if;

  normalized_reason := nullif(trim(coalesce(p_reason, '')), '');
  if normalized_reason is null or char_length(normalized_reason) < 2 then
    raise exception 'Debes indicar el motivo del movimiento';
  end if;

  select * into current_client
  from public.clients
  where id = p_client_id
  for update;

  if current_client.id is null then
    raise exception 'Cliente no encontrado';
  end if;

  if not current_client.is_active then
    raise exception 'El cliente está inactivo. Reactívalo antes de registrar movimientos';
  end if;

  new_balance := current_client.credit_balance + coalesce(p_credit_amount, 0);
  if new_balance < 0 then
    raise exception 'El saldo no puede quedar negativo';
  end if;

  new_purchase_count := current_client.purchase_count + case when p_action_type = 'purchase' then 1 else 0 end;
  new_story_count := current_client.instagram_story_count + case when p_action_type = 'instagram_story' then 1 else 0 end;
  new_referral_count := current_client.referral_count + case when p_action_type = 'referral' then 1 else 0 end;

  update public.clients
  set purchase_count = new_purchase_count,
      instagram_story_count = new_story_count,
      referral_count = new_referral_count,
      credit_balance = new_balance
  where id = p_client_id;

  insert into public.client_events (
    client_id,
    event_type,
    description,
    credit_amount,
    metadata,
    created_by
  ) values (
    p_client_id,
    p_action_type,
    normalized_reason,
    coalesce(p_credit_amount, 0),
    jsonb_build_object(
      'purchase_count', new_purchase_count,
      'instagram_story_count', new_story_count,
      'referral_count', new_referral_count
    ),
    auth.uid()
  ) returning id into event_id;

  if coalesce(p_credit_amount, 0) <> 0 then
    insert into public.credit_movements (
      client_id,
      client_event_id,
      action_type,
      amount,
      reason,
      balance_after,
      created_by
    ) values (
      p_client_id,
      event_id,
      p_action_type,
      p_credit_amount,
      normalized_reason,
      new_balance,
      auth.uid()
    );
  end if;

  return jsonb_build_object(
    'client_id', p_client_id,
    'event_id', event_id,
    'credit_balance', new_balance,
    'purchase_count', new_purchase_count,
    'instagram_story_count', new_story_count,
    'referral_count', new_referral_count
  );
end;
$$;

create or replace function public.admin_redeem_reward(
  p_client_id uuid,
  p_reward_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_client public.clients;
  selected_reward public.rewards;
  new_balance integer;
  event_id uuid;
  redemption_id uuid;
  redemption_reason text;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  select * into current_client
  from public.clients
  where id = p_client_id
  for update;

  if current_client.id is null then
    raise exception 'Cliente no encontrado';
  end if;

  if not current_client.is_active then
    raise exception 'El cliente está inactivo';
  end if;

  select * into selected_reward
  from public.rewards
  where id = p_reward_id
  for update;

  if selected_reward.id is null or not selected_reward.is_active then
    raise exception 'Recompensa no disponible';
  end if;

  if selected_reward.stock is not null and selected_reward.stock <= 0 then
    raise exception 'La recompensa no tiene stock';
  end if;

  if current_client.credit_balance < selected_reward.credits_required then
    raise exception 'El cliente no tiene créditos suficientes';
  end if;

  new_balance := current_client.credit_balance - selected_reward.credits_required;
  redemption_reason := 'Canje de recompensa: ' || selected_reward.name;

  update public.clients
  set credit_balance = new_balance
  where id = p_client_id;

  if selected_reward.stock is not null then
    update public.rewards
    set stock = stock - 1
    where id = p_reward_id;
  end if;

  insert into public.client_events (
    client_id,
    event_type,
    description,
    credit_amount,
    metadata,
    created_by
  ) values (
    p_client_id,
    'reward_redemption',
    redemption_reason,
    -selected_reward.credits_required,
    jsonb_build_object('reward_id', p_reward_id, 'reward_name', selected_reward.name),
    auth.uid()
  ) returning id into event_id;

  insert into public.credit_movements (
    client_id,
    client_event_id,
    action_type,
    amount,
    reason,
    balance_after,
    created_by
  ) values (
    p_client_id,
    event_id,
    'reward_redemption',
    -selected_reward.credits_required,
    redemption_reason,
    new_balance,
    auth.uid()
  );

  insert into public.reward_redemptions (
    client_id,
    reward_id,
    client_event_id,
    credits_spent,
    status,
    notes,
    redeemed_by
  ) values (
    p_client_id,
    p_reward_id,
    event_id,
    selected_reward.credits_required,
    'pending',
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
  ) returning id into redemption_id;

  return jsonb_build_object(
    'redemption_id', redemption_id,
    'credit_balance', new_balance,
    'status', 'pending'
  );
end;
$$;

create or replace function public.admin_update_redemption_status(
  p_redemption_id uuid,
  p_status text,
  p_notes text default null
)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_redemption public.reward_redemptions;
  current_client public.clients;
  selected_reward public.rewards;
  new_balance integer;
  reversal_event_id uuid;
  updated_redemption public.reward_redemptions;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  if p_status not in ('pending', 'approved', 'delivered', 'cancelled') then
    raise exception 'Estado de canje inválido';
  end if;

  select * into current_redemption
  from public.reward_redemptions
  where id = p_redemption_id
  for update;

  if current_redemption.id is null then
    raise exception 'Canje no encontrado';
  end if;

  if current_redemption.status = 'cancelled' and p_status <> 'cancelled' then
    raise exception 'Un canje cancelado no puede reactivarse';
  end if;

  if p_status = 'cancelled' and current_redemption.status <> 'cancelled' then
    select * into current_client
    from public.clients
    where id = current_redemption.client_id
    for update;

    select * into selected_reward
    from public.rewards
    where id = current_redemption.reward_id
    for update;

    new_balance := current_client.credit_balance + current_redemption.credits_spent;

    update public.clients
    set credit_balance = new_balance
    where id = current_redemption.client_id;

    if selected_reward.stock is not null then
      update public.rewards
      set stock = stock + 1
      where id = current_redemption.reward_id;
    end if;

    insert into public.client_events (
      client_id,
      event_type,
      description,
      credit_amount,
      metadata,
      created_by
    ) values (
      current_redemption.client_id,
      'reward_reversal',
      'Reintegro por cancelación de canje: ' || selected_reward.name,
      current_redemption.credits_spent,
      jsonb_build_object('redemption_id', current_redemption.id, 'reward_id', selected_reward.id),
      auth.uid()
    ) returning id into reversal_event_id;

    insert into public.credit_movements (
      client_id,
      client_event_id,
      action_type,
      amount,
      reason,
      balance_after,
      created_by
    ) values (
      current_redemption.client_id,
      reversal_event_id,
      'reward_reversal',
      current_redemption.credits_spent,
      'Reintegro por cancelación de canje: ' || selected_reward.name,
      new_balance,
      auth.uid()
    );
  end if;

  update public.reward_redemptions
  set status = p_status,
      notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes)
  where id = p_redemption_id
  returning * into updated_redemption;

  return updated_redemption;
end;
$$;

create or replace function public.admin_search_clients(p_query text default '')
returns table (
  id uuid,
  client_code text,
  access_token text,
  full_name text,
  phone text,
  instagram_username text,
  joined_at date,
  purchase_count integer,
  instagram_story_count integer,
  referral_count integer,
  credit_balance integer,
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
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  return query
  select
    c.id,
    c.client_code,
    c.access_token,
    c.full_name,
    c.phone,
    c.instagram_username,
    c.joined_at,
    c.purchase_count,
    c.instagram_story_count,
    c.referral_count,
    c.credit_balance,
    c.is_active,
    c.internal_notes,
    c.created_at,
    c.updated_at
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

create or replace function public.admin_get_client_history(p_client_id uuid)
returns table (
  id uuid,
  event_type text,
  description text,
  credit_amount integer,
  balance_after integer,
  created_at timestamptz,
  admin_name text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  return query
  select
    e.id,
    e.event_type,
    e.description,
    e.credit_amount,
    m.balance_after,
    e.created_at,
    a.full_name as admin_name
  from public.client_events e
  left join public.credit_movements m on m.client_event_id = e.id
  left join public.admins a on a.id = e.created_by
  where e.client_id = p_client_id
  order by e.created_at desc;
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
  if not public.is_admin(auth.uid()) then
    raise exception 'No autorizado';
  end if;

  return jsonb_build_object(
    'clients_total', (select count(*) from public.clients),
    'clients_active', (select count(*) from public.clients where is_active),
    'clients_inactive', (select count(*) from public.clients where not is_active),
    'purchases_total', (select coalesce(sum(purchase_count), 0) from public.clients),
    'stories_total', (select coalesce(sum(instagram_story_count), 0) from public.clients),
    'referrals_total', (select coalesce(sum(referral_count), 0) from public.clients),
    'credits_in_circulation', (select coalesce(sum(credit_balance), 0) from public.clients),
    'credits_issued', (select coalesce(sum(amount), 0) from public.credit_movements where amount > 0),
    'credits_spent', (select coalesce(abs(sum(amount)), 0) from public.credit_movements where amount < 0),
    'rewards_active', (select count(*) from public.rewards where is_active),
    'redemptions_pending', (select count(*) from public.reward_redemptions where status = 'pending')
  );
end;
$$;

create or replace function public.get_client_card_by_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  selected_client public.clients;
  next_reward jsonb;
  available_rewards jsonb;
  all_rewards jsonb;
  recent_history jsonb;
  progress_percent integer;
begin
  if p_token is null or char_length(trim(p_token)) < 32 then
    return null;
  end if;

  select * into selected_client
  from public.clients
  where access_token = trim(p_token)
  limit 1;

  if selected_client.id is null then
    return null;
  end if;

  select to_jsonb(r)
  into next_reward
  from (
    select id, name, description, credits_required, stock
    from public.rewards
    where is_active = true
      and credits_required > selected_client.credit_balance
      and (stock is null or stock > 0)
    order by credits_required asc, display_order asc
    limit 1
  ) r;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.credits_required, r.display_order), '[]'::jsonb)
  into available_rewards
  from (
    select id, name, description, credits_required, stock, display_order
    from public.rewards
    where is_active = true
      and credits_required <= selected_client.credit_balance
      and (stock is null or stock > 0)
  ) r;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.credits_required, r.display_order), '[]'::jsonb)
  into all_rewards
  from (
    select id, name, description, credits_required, stock, display_order,
           (credits_required <= selected_client.credit_balance and (stock is null or stock > 0)) as is_available
    from public.rewards
    where is_active = true
  ) r;

  select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc), '[]'::jsonb)
  into recent_history
  from (
    select
      e.id,
      e.event_type,
      e.description,
      e.credit_amount,
      m.balance_after,
      e.created_at
    from public.client_events e
    left join public.credit_movements m on m.client_event_id = e.id
    where e.client_id = selected_client.id
    order by e.created_at desc
    limit 50
  ) h;

  if next_reward is null then
    progress_percent := 100;
  else
    progress_percent := least(
      100,
      floor((selected_client.credit_balance::numeric / greatest((next_reward->>'credits_required')::integer, 1)) * 100)::integer
    );
  end if;

  return jsonb_build_object(
    'client', jsonb_build_object(
      'full_name', selected_client.full_name,
      'client_code', selected_client.client_code,
      'joined_at', selected_client.joined_at,
      'purchase_count', selected_client.purchase_count,
      'instagram_story_count', selected_client.instagram_story_count,
      'referral_count', selected_client.referral_count,
      'credit_balance', selected_client.credit_balance,
      'is_active', selected_client.is_active
    ),
    'progress_percent', progress_percent,
    'next_reward', next_reward,
    'available_rewards', available_rewards,
    'rewards', all_rewards,
    'history', recent_history
  );
end;
$$;

alter table public.admins enable row level security;
alter table public.clients enable row level security;
alter table public.client_events enable row level security;
alter table public.credit_movements enable row level security;
alter table public.rewards enable row level security;
alter table public.reward_redemptions enable row level security;

drop policy if exists admins_select_own_or_admin on public.admins;
create policy admins_select_own_or_admin
on public.admins
for select
to authenticated
using (id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists clients_admin_select on public.clients;
create policy clients_admin_select
on public.clients
for select
to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists client_events_admin_select on public.client_events;
create policy client_events_admin_select
on public.client_events
for select
to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists credit_movements_admin_select on public.credit_movements;
create policy credit_movements_admin_select
on public.credit_movements
for select
to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists rewards_admin_select on public.rewards;
create policy rewards_admin_select
on public.rewards
for select
to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists rewards_admin_insert on public.rewards;
create policy rewards_admin_insert
on public.rewards
for insert
to authenticated
with check (public.is_admin(auth.uid()));

drop policy if exists rewards_admin_update on public.rewards;
create policy rewards_admin_update
on public.rewards
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists rewards_admin_delete on public.rewards;
create policy rewards_admin_delete
on public.rewards
for delete
to authenticated
using (public.is_admin(auth.uid()));

drop policy if exists reward_redemptions_admin_select on public.reward_redemptions;
create policy reward_redemptions_admin_select
on public.reward_redemptions
for select
to authenticated
using (public.is_admin(auth.uid()));

revoke all on table public.admins from anon, authenticated;
revoke all on table public.clients from anon, authenticated;
revoke all on table public.client_events from anon, authenticated;
revoke all on table public.credit_movements from anon, authenticated;
revoke all on table public.rewards from anon, authenticated;
revoke all on table public.reward_redemptions from anon, authenticated;

-- Los administradores autenticados solo leen tablas directamente.
-- Las escrituras sensibles se realizan mediante funciones RPC.
grant select on table public.admins to authenticated;
grant select on table public.clients to authenticated;
grant select on table public.client_events to authenticated;
grant select on table public.credit_movements to authenticated;
grant select, insert, update, delete on table public.rewards to authenticated;
grant select on table public.reward_redemptions to authenticated;

grant usage, select on sequence public.client_code_seq to postgres;

-- Revocar el permiso EXECUTE público por defecto en las funciones del proyecto.
do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'set_updated_at',
        'is_admin',
        'generate_client_code',
        'generate_client_token',
        'prepare_client_insert',
        'admin_create_client',
        'admin_update_client',
        'admin_set_client_status',
        'admin_delete_client',
        'admin_register_action',
        'admin_redeem_reward',
        'admin_update_redemption_status',
        'admin_search_clients',
        'admin_get_client_history',
        'admin_get_stats',
        'get_client_card_by_token'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn.signature);
  end loop;
end;
$$;

grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.admin_create_client(text, text, text, date, text) to authenticated;
grant execute on function public.admin_update_client(uuid, text, text, text, date, text) to authenticated;
grant execute on function public.admin_set_client_status(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_client(uuid) to authenticated;
grant execute on function public.admin_register_action(uuid, text, integer, text) to authenticated;
grant execute on function public.admin_redeem_reward(uuid, uuid, text) to authenticated;
grant execute on function public.admin_update_redemption_status(uuid, text, text) to authenticated;
grant execute on function public.admin_search_clients(text) to authenticated;
grant execute on function public.admin_get_client_history(uuid) to authenticated;
grant execute on function public.admin_get_stats() to authenticated;
grant execute on function public.get_client_card_by_token(text) to anon, authenticated;

-- Verificación final visible en Results
select
  to_regclass('public.admins') is not null as admins_ok,
  to_regclass('public.clients') is not null as clients_ok,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'clients'
      and column_name = 'phone'
  ) as phone_ok,
  to_regclass('public.credit_movements') is not null as movements_ok,
  to_regclass('public.rewards') is not null as rewards_ok;
