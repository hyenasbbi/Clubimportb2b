-- CLUB IMPORTB2B V3 — MIGRACIÓN SEGURA MULTI-CLUB
-- Basado en el schema V2 actual de hyenasbbi/Clubimportb2b.
-- NO elimina clientes, códigos, tokens, acciones, claims ni historial.
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

-- Copia la membresía actual de cada cliente. No duplica personas.
insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
select id,club_type,points,is_active,joined_at from public.clients
on conflict(client_id,club_type) do update
set points=greatest(public.client_clubs.points,excluded.points),
    is_active=excluded.is_active;

create index if not exists client_clubs_client_idx on public.client_clubs(client_id);
create index if not exists client_clubs_type_idx on public.client_clubs(club_type);

drop trigger if exists client_clubs_set_updated_at on public.client_clubs;
create trigger client_clubs_set_updated_at before update on public.client_clubs
for each row execute function public.set_updated_at();

alter table public.client_clubs enable row level security;
drop policy if exists client_clubs_admin_select on public.client_clubs;
create policy client_clubs_admin_select on public.client_clubs for select to authenticated
using(public.is_admin(auth.uid()));

-- Vapers deja de ser infinito cada 3: ahora metas visibles 3 / 6 / 9.
delete from public.club_reward_rules where club_type='vapers';
insert into public.club_reward_rules
(club_type,milestone,reward_name,reward_description,recurring_every,display_order,is_active)
values
('vapers',3,'Recompensa Vapers I','Premio desbloqueado en la compra válida número 3.',null,1,true),
('vapers',6,'Recompensa Vapers II','Premio desbloqueado en la compra válida número 6.',null,2,true),
('vapers',9,'Recompensa Vapers III','Premio desbloqueado en la compra válida número 9.',null,3,true)
on conflict(club_type,milestone) do update set
reward_name=excluded.reward_name,reward_description=excluded.reward_description,
recurring_every=null,display_order=excluded.display_order,is_active=true;

create or replace function public.admin_add_client_to_club(p_client_id uuid,p_club_type text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare t text:=lower(trim(coalesce(p_club_type,''))); r public.client_clubs;
begin
 if not public.is_admin(auth.uid()) then raise exception 'No autorizado'; end if;
 if t not in ('vapers','jerseys','perfumes','importb2b') then raise exception 'Club inválido'; end if;
 if not exists(select 1 from public.clients where id=p_client_id) then raise exception 'Cliente no encontrado'; end if;
 insert into public.client_clubs(client_id,club_type,points,is_active)
 values(p_client_id,t,0,true)
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
 update public.client_clubs set points=new_points where id=m.id;
 insert into public.club_actions(client_id,club_type,purchase_amount,observation,created_by)
 values(c.id,t,p_purchase_amount,nullif(trim(coalesce(p_observation,'')),''),auth.uid()) returning id into action_id;
 update public.clients set purchase_count=purchase_count+1,instagram_story_count=instagram_story_count+1 where id=c.id;
 insert into public.client_events(client_id,event_type,description,metadata,created_by)
 values(c.id,'verified_purchase_story','Compra + historia verificadas · '||public.club_display_name(t),
 jsonb_build_object('club_type',t,'point_added',1,'points_after',new_points,'club_action_id',action_id),auth.uid());
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
 return jsonb_build_object('client_id',c.id,'club_type',t,'points',new_points,'reward_unlocked',reward_rec.reward_name,'claim_id',claim_id);
end $$;

grant select on public.client_clubs to authenticated;
grant execute on function public.admin_add_client_to_club(uuid,text) to authenticated;
grant execute on function public.admin_get_client_clubs(uuid) to authenticated;
grant execute on function public.admin_register_verified_purchase_v3(uuid,text,numeric,text) to authenticated;

commit;

-- VERIFICACIÓN
select c.client_code,c.full_name,
       jsonb_agg(jsonb_build_object('club',cc.club_type,'points',cc.points) order by cc.club_type) clubs
from public.clients c join public.client_clubs cc on cc.client_id=c.id
group by c.id,c.client_code,c.full_name order by c.created_at desc;
