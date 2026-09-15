(function clientCardV32(){
  "use strict";
  const db=window.clubSupabase;
  const $=id=>document.getElementById(id);
  const labels={vapers:"Club Vapers",jerseys:"Club Jerseys",perfumes:"Club Perfumes",importb2b:"Club IMPORTB2B"};
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const fmtDate=v=>{if(!v)return"—";const d=new Date(String(v).length===10?v+"T12:00:00":v);return Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("es-AR",{dateStyle:"medium"}).format(d)};
  const token=()=>{const p=location.pathname.split("/").filter(Boolean),i=p.indexOf("c");return i>=0&&p[i+1]?decodeURIComponent(p[i+1]).trim():(new URLSearchParams(location.search).get("token")||"").trim()};
  const fail=m=>{$("loadingState").hidden=true;$('cardContent').hidden=true;$('errorMessage').textContent=m;$('errorState').hidden=false};

  function rewardHtml(r){
    const status=r.status||"locked";
    const label=status==="delivered"?"Entregado":status==="unlocked"?"Desbloqueado":`Faltan ${Number(r.remaining||0)}`;
    return `<div class="mc-reward ${status}"><div><b>${esc(r.reward_name)}</b><small>Meta: ${Number(r.milestone||0)} puntos</small><p>${esc(r.description||"")}</p></div><span>${esc(label)}</span></div>`;
  }

  function historyHtml(items){
    const arr=Array.isArray(items)?items:[];
    if(!arr.length)return '<div class="mc-empty">Todavía no hay movimientos en este club.</div>';
    return arr.map(h=>`<div class="mc-history-item"><span class="mc-history-dot"></span><div><strong>${esc(h.description||"Movimiento")}</strong><small>${esc(fmtDate(h.created_at))}</small></div></div>`).join("");
  }

  function clubCard(c,index){
    const n=c.next_reward;
    const progress=n?Math.max(0,Math.min(100,Number(n.progress_percent||0))):100;
    const nextText=n?`${Number(c.points||0)} / ${Number(n.milestone||0)} puntos · ${esc(n.name)}`:"Metas actuales completadas";
    return `<details class="mc-club-card" ${index===0?"open":""}>
      <summary class="mc-club-summary">
        <div class="mc-club-title"><small>${esc(labels[c.club_type]||c.club_name||"Club")}</small><strong>${Number(c.points||0)} puntos</strong><span>${esc(nextText)}</span></div>
        <div class="mc-club-summary-right"><span class="status-badge ${c.is_active?"is-active":"is-inactive"}">${c.is_active?"Activo":"Inactivo"}</span><span class="mc-chevron">⌄</span></div>
      </summary>
      <div class="mc-club-body">
        <div class="mc-progress-meta"><span>${n?`Próxima meta: ${Number(n.milestone)} puntos`:"Progreso completo"}</span><strong>${progress}%</strong></div>
        <div class="mc-progress"><span style="width:${progress}%"></span></div>
        ${n?`<p class="mc-next">Te faltan <strong>${Number(n.remaining||0)}</strong> puntos para <strong>${esc(n.name)}</strong>.</p>`:'<p class="mc-next">Alcanzaste todas las recompensas configuradas actualmente para este club.</p>'}
        <div class="mc-subsection"><h3>Recompensas</h3><div class="mc-rewards">${(c.rewards||[]).map(rewardHtml).join("")||'<div class="mc-empty">No hay recompensas configuradas.</div>'}</div></div>
        <div class="mc-subsection"><h3>Historial de este club</h3><div class="mc-history">${historyHtml(c.history)}</div></div>
      </div>
    </details>`;
  }

  async function load(){
    if(!window.CLUB_CONFIG_READY||!db){fail("El sitio todavía no está conectado con Supabase.");return;}
    const t=token(); if(!t){fail("Este enlace no contiene un token válido.");return;}
    try{
      const {data,error}=await db.rpc("get_client_card_by_token",{p_token:t});
      if(error)throw error;
      if(!data?.client){fail("No encontramos una tarjeta asociada a este enlace.");return;}
      const c=data.client,clubs=Array.isArray(data.clubs)?data.clubs:[];
      const totalPoints=clubs.reduce((s,x)=>s+Number(x.points||0),0);
      const box=$("cardContent");
      box.innerHTML=`
        <section class="client-intro"><div><span class="eyebrow">TU ESPACIO EN IMPORTB2B</span><h1>Hola, ${esc(c.full_name)}</h1><p>Un solo código. Todos tus clubes y progresos por separado.</p></div><span class="status-badge ${c.is_active?"is-active":"is-inactive"}">${c.is_active?"Miembro activo":"Miembro inactivo"}</span></section>
        <section class="membership-card mc-master-card"><div class="membership-card__top"><div><small>CLUB IMPORTB2B</small><strong>MEMBER CARD</strong></div><img src="/assets/logo-importb2b.png" class="brand-logo brand-logo--card" alt="IMPORTB2B"></div><div class="mc-master-stats"><div><small>CÓDIGO ÚNICO</small><strong>${esc(c.client_code)}</strong></div><div><small>CLUBES ACTIVOS</small><strong>${clubs.filter(x=>x.is_active).length}</strong></div><div><small>PUNTOS TOTALES</small><strong>${totalPoints}</strong></div></div><div class="membership-card__footer"><div><small>MIEMBRO DESDE</small><strong>${esc(fmtDate(c.joined_at))}</strong></div><div><small>ESTADO</small><strong>${c.is_active?"ACTIVO":"INACTIVO"}</strong></div></div></section>
        <section class="verification-banner"><strong>¿Qué suma un punto?</strong><span>Una compra + una historia etiquetando a @import.b2b, verificadas por el equipo. El punto se acredita únicamente al club correspondiente.</span></section>
        <section class="metric-grid metric-grid--client"><article class="metric-card"><strong>${Number(data.valid_actions||0)}</strong><small>Compras + historias válidas</small></article><article class="metric-card"><strong>${Number(data.unlocked_rewards_count||0)}</strong><small>Premios pendientes</small></article><article class="metric-card"><strong>${Number(data.delivered_rewards_count||0)}</strong><small>Premios entregados</small></article></section>
        <section class="content-section"><div class="section-heading"><div><span class="eyebrow">TUS MEMBRESÍAS</span><h2>Progreso por club</h2></div><p>Abrí cada tarjeta para ver metas, premios e historial.</p></div><div class="mc-club-list">${clubs.map(clubCard).join("")||'<div class="empty-state">Este cliente todavía no tiene clubes asignados.</div>'}</div></section>`;
      $("loadingState").hidden=true;$("errorState").hidden=true;box.hidden=false;
    }catch(e){console.error(e);fail("No fue posible cargar la tarjeta. Inténtalo nuevamente.");}
  }
  load();
})();
