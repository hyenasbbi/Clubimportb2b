-- CLUB IMPORTB2B V3.1 — soporte frontend Multi-Club
begin;

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

insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
select id,club_type,points,is_active,joined_at from public.clients
on conflict(client_id,club_type) do nothing;

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
grant execute on function public.admin_find_existing_client(text,text) to authenticated;

create or replace function public.get_client_card_by_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.clients; clubs_json jsonb; history_json jsonb;
        pending_count int; delivered_count int; valid_actions int;
begin
 select * into c from public.clients where access_token=p_token limit 1;
 if c.id is null then return null; end if;

 select coalesce(jsonb_agg(x.obj order by x.sort_order),'[]'::jsonb) into clubs_json
 from (
  select case cc.club_type when 'vapers' then 1 when 'jerseys' then 2 when 'perfumes' then 3 else 4 end sort_order,
   jsonb_build_object(
    'club_type',cc.club_type,'club_name',public.club_display_name(cc.club_type),
    'points',cc.points,'is_active',cc.is_active,'joined_at',cc.joined_at,
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
      where r.club_type=cc.club_type and r.is_active),'[]'::jsonb)
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
commit;

select c.client_code,c.full_name,
 jsonb_agg(jsonb_build_object('club',cc.club_type,'points',cc.points) order by cc.club_type) clubs
from public.clients c join public.client_clubs cc on cc.client_id=c.id
where c.client_code in ('IMP-000004','IMP-000017')
group by c.id,c.client_code,c.full_name order by c.client_code;
