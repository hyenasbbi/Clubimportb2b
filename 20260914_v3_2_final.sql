-- CLUB IMPORTB2B V3.2 FINAL — Multi-Club consistente
-- No elimina clientes ni historial. Hace client_clubs la fuente de verdad para progreso.
begin;

create table if not exists public.client_clubs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  club_type text not null check (club_type in ('vapers','jerseys','perfumes','importb2b')),
  points integer not null default 0 check(points >= 0),
  is_active boolean not null default true,
  joined_at date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(client_id, club_type)
);

-- Garantiza que toda ficha existente tenga al menos su membresía legacy copiada.
insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
select id,club_type,coalesce(points,0),is_active,joined_at from public.clients
on conflict(client_id,club_type) do nothing;

create or replace function public.sync_new_client_initial_club()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
  values(new.id,new.club_type,coalesce(new.points,0),new.is_active,new.joined_at)
  on conflict(client_id,club_type) do nothing;
  return new;
end $$;

drop trigger if exists clients_sync_initial_club on public.clients;
create trigger clients_sync_initial_club after insert on public.clients
for each row execute function public.sync_new_client_initial_club();

-- Vapers explícito: 3 / 6 / 9.
update public.club_reward_rules
set recurring_every=null,
    reward_name='Recompensa Vapers I',
    reward_description='Primera recompensa del Club Vapers.'
where club_type='vapers' and milestone=3;

insert into public.club_reward_rules
(club_type,milestone,reward_name,reward_description,recurring_every,display_order,is_active)
values
('vapers',6,'Recompensa Vapers II','Segunda recompensa del Club Vapers.',null,2,true),
('vapers',9,'Recompensa Vapers III','Tercera recompensa del Club Vapers.',null,3,true)
on conflict(club_type,milestone) do update set
 reward_name=excluded.reward_name,
 reward_description=excluded.reward_description,
 recurring_every=null,
 display_order=excluded.display_order,
 is_active=true;

create or replace function public.admin_find_existing_client(p_instagram text default null,p_phone text default null)
returns table(id uuid,client_code text,full_name text,instagram_username text,phone text)
language plpgsql stable security definer set search_path=public,auth as $$
declare i text:=lower(coalesce(public.normalize_instagram_username(p_instagram),''));
        ph text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 return query select c.id,c.client_code,c.full_name,c.instagram_username,c.phone
 from public.clients c
 where (i<>'' and lower(coalesce(c.instagram_username,''))=i)
    or (ph<>'' and regexp_replace(coalesce(c.phone,''),'\D','','g')=ph)
 order by c.created_at asc limit 5;
end $$;

create or replace function public.admin_search_clients_v3(p_query text default '')
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare q text:=trim(coalesce(p_query,'')); result jsonb;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 select coalesce(jsonb_agg(obj order by created_at desc),'[]'::jsonb) into result
 from (
   select c.created_at,
     jsonb_build_object(
       'id',c.id,'client_code',c.client_code,'access_token',c.access_token,
       'full_name',c.full_name,'phone',c.phone,'instagram_username',c.instagram_username,
       'joined_at',c.joined_at,'is_active',c.is_active,'internal_notes',c.internal_notes,
       'created_at',c.created_at,'updated_at',c.updated_at,
       'clubs',coalesce((select jsonb_agg(jsonb_build_object(
          'club_type',cc.club_type,'points',cc.points,'is_active',cc.is_active,'joined_at',cc.joined_at
        ) order by case cc.club_type when 'vapers' then 1 when 'jerseys' then 2 when 'perfumes' then 3 else 4 end)
        from public.client_clubs cc where cc.client_id=c.id),'[]'::jsonb)
     ) obj
   from public.clients c
   where q='' or c.full_name ilike '%'||q||'%'
      or coalesce(c.phone,'') ilike '%'||q||'%'
      or coalesce(c.instagram_username,'') ilike '%'||trim(leading '@' from q)||'%'
      or c.client_code ilike '%'||q||'%'
   limit 500
 ) s;
 return result;
end $$;

create or replace function public.admin_get_stats_v3()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 return jsonb_build_object(
   'clients_total',(select count(*) from public.clients),
   'clients_active',(select count(*) from public.clients where is_active),
   'valid_actions_total',(select coalesce(sum(points),0) from public.client_clubs),
   'rewards_unlocked',(select count(*) from public.reward_claims),
   'rewards_pending',(select count(*) from public.reward_claims where status='pending'),
   'club_vapers',(select count(*) from public.client_clubs where club_type='vapers' and is_active),
   'club_jerseys',(select count(*) from public.client_clubs where club_type='jerseys' and is_active),
   'club_perfumes',(select count(*) from public.client_clubs where club_type='perfumes' and is_active),
   'club_importb2b',(select count(*) from public.client_clubs where club_type='importb2b' and is_active)
 );
end $$;

create or replace function public.admin_create_client_v3(
 p_full_name text,p_phone text default null,p_instagram_username text default null,
 p_joined_at date default current_date,p_internal_notes text default null,p_club_type text default 'importb2b')
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare t text:=lower(trim(coalesce(p_club_type,''))); c public.clients; existing_id uuid;
        i text:=lower(coalesce(public.normalize_instagram_username(p_instagram_username),''));
        ph text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 if char_length(trim(coalesce(p_full_name,'')))<2 then raise exception 'El nombre es obligatorio'; end if;
 if t not in ('vapers','jerseys','perfumes','importb2b') then raise exception 'Club inválido'; end if;
 select id into existing_id from public.clients x where
   (i<>'' and lower(coalesce(x.instagram_username,''))=i) or
   (ph<>'' and regexp_replace(coalesce(x.phone,''),'\D','','g')=ph)
 limit 1;
 if existing_id is not null then raise exception 'Este cliente ya existe. Abrí su ficha y agregalo al nuevo club.'; end if;
 insert into public.clients(full_name,phone,instagram_username,joined_at,internal_notes,club_type,points,created_by)
 values(trim(p_full_name),nullif(trim(coalesce(p_phone,'')),''),public.normalize_instagram_username(p_instagram_username),
        coalesce(p_joined_at,current_date),nullif(trim(coalesce(p_internal_notes,'')),''),t,0,auth.uid())
 returning * into c;
 insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
 values(c.id,t,0,true,c.joined_at) on conflict(client_id,club_type) do nothing;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(c.id,'client_created','Ingreso al '||public.club_display_name(t),jsonb_build_object('club_type',t,'points_after',0),auth.uid());
 return jsonb_build_object('id',c.id,'client_code',c.client_code,'access_token',c.access_token);
end $$;

create or replace function public.admin_update_client_v3(
 p_client_id uuid,p_full_name text,p_phone text default null,p_instagram_username text default null,
 p_joined_at date default current_date,p_internal_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare c public.clients;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 if char_length(trim(coalesce(p_full_name,'')))<2 then raise exception 'El nombre es obligatorio'; end if;
 update public.clients set
   full_name=trim(p_full_name),
   phone=nullif(trim(coalesce(p_phone,'')),''),
   instagram_username=public.normalize_instagram_username(p_instagram_username),
   joined_at=coalesce(p_joined_at,joined_at),
   internal_notes=nullif(trim(coalesce(p_internal_notes,'')),'')
 where id=p_client_id returning * into c;
 if c.id is null then raise exception 'Cliente no encontrado'; end if;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(c.id,'client_updated','Datos del cliente actualizados','{}'::jsonb,auth.uid());
 return jsonb_build_object('id',c.id,'client_code',c.client_code);
end $$;

create or replace function public.admin_set_client_status_v3(p_client_id uuid,p_is_active boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare c public.clients;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 update public.clients set is_active=p_is_active where id=p_client_id returning * into c;
 if c.id is null then raise exception 'Cliente no encontrado'; end if;
 update public.client_clubs set is_active=p_is_active,updated_at=now() where client_id=p_client_id;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(c.id,'status_change',case when p_is_active then 'Cliente reactivado' else 'Cliente desactivado' end,
        jsonb_build_object('is_active',p_is_active),auth.uid());
 return jsonb_build_object('id',c.id,'is_active',p_is_active);
end $$;

create or replace function public.admin_add_client_to_club(p_client_id uuid,p_club_type text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare t text:=lower(trim(coalesce(p_club_type,''))); r public.client_clubs; j date;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 if t not in ('vapers','jerseys','perfumes','importb2b') then raise exception 'Club inválido'; end if;
 select joined_at into j from public.clients where id=p_client_id;
 if j is null then raise exception 'Cliente no encontrado'; end if;
 insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
 values(p_client_id,t,0,true,j)
 on conflict(client_id,club_type) do update set is_active=true,updated_at=now()
 returning * into r;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(p_client_id,'client_updated','Cliente agregado a '||public.club_display_name(t),
        jsonb_build_object('club_type',t,'action','club_added'),auth.uid());
 return jsonb_build_object('client_id',r.client_id,'club_type',r.club_type,'points',r.points);
end $$;

create or replace function public.admin_get_client_clubs(p_client_id uuid)
returns table(club_type text,points integer,is_active boolean,joined_at date)
language plpgsql stable security definer set search_path=public,auth as $$
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 return query select cc.club_type,cc.points,cc.is_active,cc.joined_at
 from public.client_clubs cc where cc.client_id=p_client_id
 order by case cc.club_type when 'vapers' then 1 when 'jerseys' then 2 when 'perfumes' then 3 else 4 end;
end $$;

create or replace function public.admin_register_verified_purchase_v3(
 p_client_id uuid,p_club_type text,p_purchase_amount numeric default null,p_observation text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare t text:=lower(trim(coalesce(p_club_type,''))); c public.clients; m public.client_clubs;
 new_points integer; action_id uuid; reward_rec public.club_reward_rules; claim_id uuid;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 if t not in ('vapers','jerseys','perfumes','importb2b') then raise exception 'Club inválido'; end if;
 select * into c from public.clients where id=p_client_id for update;
 if c.id is null then raise exception 'Cliente no encontrado'; end if;
 if not c.is_active then raise exception 'El cliente está inactivo'; end if;
 select * into m from public.client_clubs where client_id=p_client_id and club_type=t for update;
 if m.id is null or not m.is_active then raise exception 'El cliente no pertenece a ese club'; end if;
 if t='importb2b' and (p_purchase_amount is null or p_purchase_amount<30000) then
   raise exception 'Club IMPORTB2B requiere compra mínima de $30.000';
 end if;
 new_points:=m.points+1;
 update public.client_clubs set points=new_points,updated_at=now() where id=m.id;
 insert into public.club_actions(client_id,club_type,purchase_amount,observation,created_by)
 values(c.id,t,p_purchase_amount,nullif(trim(coalesce(p_observation,'')),''),auth.uid()) returning id into action_id;
 update public.clients set purchase_count=purchase_count+1,instagram_story_count=instagram_story_count+1 where id=c.id;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(c.id,'verified_purchase_story','Compra + historia verificadas · '||public.club_display_name(t),
 jsonb_build_object('club_type',t,'point_added',1,'points_after',new_points,'club_action_id',action_id,
                    'purchase_amount',p_purchase_amount,'observation',nullif(trim(coalesce(p_observation,'')),'')),auth.uid());
 select * into reward_rec from public.club_reward_rules r
 where r.club_type=t and r.is_active and r.recurring_every is null and r.milestone=new_points limit 1;
 if reward_rec.id is not null then
   insert into public.reward_claims(client_id,club_type,milestone,reward_name,status)
   values(c.id,t,reward_rec.milestone,reward_rec.reward_name,'pending')
   on conflict(client_id,club_type,milestone) do nothing returning id into claim_id;
   if claim_id is not null then
     insert into public.client_events(client_id,event_type,description,metadata,created_by)
     values(c.id,'reward_unlocked','Premio desbloqueado: '||reward_rec.reward_name,
     jsonb_build_object('club_type',t,'milestone',reward_rec.milestone,'claim_id',claim_id),auth.uid());
   end if;
 end if;
 return jsonb_build_object('client_id',c.id,'club_type',t,'points',new_points,
   'reward_unlocked',reward_rec.reward_name,'claim_id',claim_id);
end $$;

create or replace function public.get_client_card_by_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.clients; clubs_json jsonb; history_json jsonb;
        pending_count int; delivered_count int; valid_actions int;
begin
 if p_token is null or char_length(trim(p_token))<16 then return null; end if;
 select * into c from public.clients where access_token=trim(p_token) limit 1;
 if c.id is null then return null; end if;

 select coalesce(jsonb_agg(x.obj order by x.sort_order),'[]'::jsonb) into clubs_json
 from (
  select case cc.club_type when 'vapers' then 1 when 'jerseys' then 2 when 'perfumes' then 3 else 4 end sort_order,
   jsonb_build_object(
    'club_type',cc.club_type,'club_name',public.club_display_name(cc.club_type),
    'points',cc.points,'is_active',cc.is_active,'joined_at',cc.joined_at,
    'valid_actions',(select count(*) from public.club_actions ca where ca.client_id=c.id and ca.club_type=cc.club_type),
    'next_reward',(select jsonb_build_object('name',r.reward_name,'description',r.reward_description,
      'milestone',r.milestone,'remaining',greatest(r.milestone-cc.points,0),
      'progress_percent',least(100,round((cc.points::numeric/nullif(r.milestone,0))*100)))
      from public.club_reward_rules r where r.club_type=cc.club_type and r.is_active and r.milestone>cc.points
      order by r.milestone limit 1),
    'rewards',coalesce((select jsonb_agg(jsonb_build_object(
      'milestone',r.milestone,'reward_name',r.reward_name,'description',r.reward_description,
      'remaining',greatest(r.milestone-cc.points,0),
      'status',case when rc.status='delivered' then 'delivered'
                    when rc.id is not null or cc.points>=r.milestone then 'unlocked' else 'locked' end)
      order by r.milestone)
      from public.club_reward_rules r left join public.reward_claims rc
       on rc.client_id=c.id and rc.club_type=r.club_type and rc.milestone=r.milestone
      where r.club_type=cc.club_type and r.is_active),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(jsonb_build_object('event_type',h.event_type,'description',h.description,
      'metadata',h.metadata,'created_at',h.created_at) order by h.created_at desc)
      from (select * from public.client_events e where e.client_id=c.id and e.metadata->>'club_type'=cc.club_type
            order by e.created_at desc limit 20) h),'[]'::jsonb)
   ) obj
  from public.client_clubs cc where cc.client_id=c.id
 ) x;

 select count(*) into valid_actions from public.club_actions where client_id=c.id;
 select count(*) filter(where status='pending'),count(*) filter(where status='delivered')
 into pending_count,delivered_count from public.reward_claims where client_id=c.id;
 select coalesce(jsonb_agg(jsonb_build_object('event_type',e.event_type,'description',e.description,
  'metadata',e.metadata,'created_at',e.created_at) order by e.created_at desc),'[]'::jsonb)
 into history_json from (select * from public.client_events where client_id=c.id order by created_at desc limit 50) e;

 return jsonb_build_object('client',jsonb_build_object('full_name',c.full_name,'client_code',c.client_code,
  'joined_at',c.joined_at,'is_active',c.is_active),'clubs',clubs_json,'valid_actions',valid_actions,
  'unlocked_rewards_count',pending_count,'delivered_rewards_count',delivered_count,'history',history_json);
end $$;

revoke all on function public.get_client_card_by_token(text) from public;
grant execute on function public.get_client_card_by_token(text) to anon,authenticated;
grant execute on function public.admin_find_existing_client(text,text) to authenticated;
grant execute on function public.admin_search_clients_v3(text) to authenticated;
grant execute on function public.admin_get_stats_v3() to authenticated;
grant execute on function public.admin_create_client_v3(text,text,text,date,text,text) to authenticated;
grant execute on function public.admin_update_client_v3(uuid,text,text,text,date,text) to authenticated;
grant execute on function public.admin_set_client_status_v3(uuid,boolean) to authenticated;
grant execute on function public.admin_add_client_to_club(uuid,text) to authenticated;
grant execute on function public.admin_get_client_clubs(uuid) to authenticated;
grant execute on function public.admin_register_verified_purchase_v3(uuid,text,numeric,text) to authenticated;

commit;

-- Verificación de lectura: una fila por cliente con todos sus clubes.
select c.client_code,c.full_name,
       jsonb_agg(jsonb_build_object('club',cc.club_type,'points',cc.points) order by cc.club_type) clubs
from public.clients c join public.client_clubs cc on cc.client_id=c.id
group by c.id,c.client_code,c.full_name order by c.client_code;
