-- SOLO PARA DUPLICADOS EXISTENTES. NO EJECUTAR SIN REEMPLAZAR LOS UUID.
-- Ejemplo Nacho: conservar MASTER_ID y absorber DUPLICATE_ID.
begin;
-- 1) mover/combinar membresías
insert into public.client_clubs(client_id,club_type,points,is_active,joined_at)
select 'MASTER_ID'::uuid, club_type, points, is_active, joined_at
from public.client_clubs where client_id='DUPLICATE_ID'::uuid
on conflict(client_id,club_type) do update
set points=public.client_clubs.points+excluded.points;

-- 2) mover historial/acciones/premios
update public.club_actions set client_id='MASTER_ID'::uuid where client_id='DUPLICATE_ID'::uuid;
update public.client_events set client_id='MASTER_ID'::uuid where client_id='DUPLICATE_ID'::uuid;
-- claims pueden chocar si ambos tenían mismo club/meta; revisar antes si ocurre:
update public.reward_claims set client_id='MASTER_ID'::uuid where client_id='DUPLICATE_ID'::uuid;

-- 3) borrar ficha duplicada recién al final
delete from public.clients where id='DUPLICATE_ID'::uuid;
commit;
