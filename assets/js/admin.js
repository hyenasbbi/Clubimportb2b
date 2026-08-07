(function adminPanel() {
  "use strict";

  const db = window.clubSupabase;
  const state = {
    user: null,
    admin: null,
    stats: {},
    clients: [],
    rules: [],
    claims: [],
    selectedClientId: null,
    toastTimer: null,
    searchTimer: null
  };

  const $ = (id) => document.getElementById(id);

  const viewTitles = {
    dashboard: "Resumen general",
    clients: "Gestión de clientes",
    rewards: "Reglas y premios",
    claims: "Premios desbloqueados"
  };

  const clubLabels = {
    vapers: "Club Vapers",
    jerseys: "Club Jerseys",
    perfumes: "Club Perfumes",
    importb2b: "Club IMPORTB2B"
  };

  const clubRules = {
    vapers: "Cada compra + historia verificada suma 1 punto. Se desbloquea un Vaper de regalo cada 3 puntos.",
    jerseys: "Cada compra + historia verificada suma 1 punto. Premios actuales: 4 puntos y 8 puntos.",
    perfumes: "Cada compra + historia verificada suma 1 punto. Premios actuales: 3, 6 y 10 puntos.",
    importb2b: "Cada compra de $30.000 o más + historia verificada suma 1 punto."
  };

  const statDefinitions = [
    ["clients_total", "Clientes totales", "Base completa"],
    ["clients_active", "Clientes activos", "Miembros habilitados"],
    ["valid_actions_total", "Puntos registrados", "Compras + historias válidas"],
    ["rewards_pending", "Premios pendientes", "Pendientes de entrega"],
    ["club_vapers", "Club Vapers", "Clientes vinculados"],
    ["club_jerseys", "Club Jerseys", "Clientes vinculados"],
    ["club_perfumes", "Club Perfumes", "Clientes vinculados"],
    ["club_importb2b", "Club IMPORTB2B", "Artículos varios"]
  ];

  const eventLabels = {
    client_created: "Ingreso al club",
    client_updated: "Actualización de datos",
    verified_purchase_story: "Compra + historia verificada",
    reward_unlocked: "Premio desbloqueado",
    reward_delivered: "Premio entregado",
    status_change: "Cambio de estado",
    other: "Movimiento",
    purchase: "Compra (registro anterior)",
    instagram_story: "Historia (registro anterior)",
    referral: "Referido (registro anterior)",
    manual_adjustment: "Ajuste anterior",
    reward_redemption: "Canje anterior",
    reward_reversal: "Reintegro anterior"
  };

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function formatDate(value, withTime) {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    return new Intl.DateTimeFormat("es-AR", {
      dateStyle: "medium",
      ...(withTime ? { timeStyle: "short" } : {})
    }).format(date);
  }

  function formatNumber(value) {
    return new Intl.NumberFormat("es-AR").format(Number(value || 0));
  }

  function formatMoney(value) {
    if (value === null || value === undefined || value === "") return "—";
    return new Intl.NumberFormat("es-AR", {
      style: "currency",
      currency: "ARS",
      maximumFractionDigits: 0
    }).format(Number(value));
  }

  function getLocalDateInputValue() {
    const date = new Date();
    const offset = date.getTimezoneOffset();
    return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 10);
  }

  function normalizeInstagram(value) {
    let result = String(value || "").trim();
    if (!result) return "";
    result = result.replace(/^https?:\/\/(www\.)?instagram\.com\//i, "");
    result = result.replace(/^www\.instagram\.com\//i, "");
    result = result.replace(/^@+/, "");
    result = result.split(/[/?#]/)[0].trim();
    return result;
  }

  function getInitials(name) {
    return String(name || "AD")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0])
      .join("")
      .toUpperCase();
  }

  function showToast(message, type) {
    const toast = $("toast");
    toast.textContent = message;
    toast.className = `toast is-visible${type === "error" ? " is-error" : ""}`;
    window.clearTimeout(state.toastTimer);
    state.toastTimer = window.setTimeout(() => {
      toast.className = "toast";
    }, 4200);
  }

  function setButtonLoading(button, loading, loadingText) {
    if (!button) return;
    if (loading) {
      button.dataset.originalText = button.textContent;
      button.disabled = true;
      button.textContent = loadingText || "Procesando...";
    } else {
      button.disabled = false;
      button.textContent = button.dataset.originalText || button.textContent;
    }
  }

  function showView(viewName) {
    document.querySelectorAll(".admin-view").forEach((view) => view.classList.remove("is-active"));
    document.querySelectorAll(".nav-button").forEach((button) => button.classList.remove("is-active"));
    $(`view-${viewName}`)?.classList.add("is-active");
    document.querySelector(`.nav-button[data-view="${viewName}"]`)?.classList.add("is-active");
    $("viewTitle").textContent = viewTitles[viewName] || "Panel administrativo";
    document.querySelector(".admin-sidebar")?.classList.remove("is-open");
    $("menuButton")?.setAttribute("aria-expanded", "false");
  }

  async function ensureAdminAccess() {
    if (!window.CLUB_CONFIG_READY || !db) {
      $("adminLoading").innerHTML = `
        <strong>Falta configurar Supabase</strong>
        <span>Revisa assets/js/config.example.js y vuelve a publicar.</span>
        <a class="button button--ghost" href="/admin/login">Volver al acceso</a>
      `;
      return false;
    }

    const { data: userData, error: userError } = await db.auth.getUser();
    if (userError || !userData.user) {
      window.location.replace("/admin/login");
      return false;
    }

    const { data: adminData, error: adminError } = await db
      .from("admins")
      .select("id, full_name, is_active")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (adminError || !adminData || !adminData.is_active) {
      await db.auth.signOut();
      window.location.replace("/admin/login");
      return false;
    }

    state.user = userData.user;
    state.admin = adminData;
    return true;
  }

  async function loadStats() {
    const { data, error } = await db.rpc("admin_get_stats");
    if (error) throw error;
    state.stats = data || {};
    $("statsGrid").innerHTML = statDefinitions.map(([key, label, note]) => `
      <article class="stat-card">
        <small>${escapeHtml(label)}</small>
        <strong>${formatNumber(state.stats[key])}</strong>
        <span>${escapeHtml(note)}</span>
      </article>
    `).join("");
  }

  async function loadClients(query) {
    const { data, error } = await db.rpc("admin_search_clients", { p_query: query || "" });
    if (error) throw error;
    state.clients = Array.isArray(data) ? data : [];
    renderClientsTable();
    renderRecentClients();
  }

  function renderClientsTable() {
    const body = $("clientsTableBody");
    $("clientsEmpty").hidden = state.clients.length > 0;

    body.innerHTML = state.clients.map((client) => `
      <tr>
        <td>
          <div class="table-client">
            <strong>${escapeHtml(client.full_name)}</strong>
            <small>${escapeHtml(client.instagram_username ? `@${client.instagram_username}` : client.phone || "Sin contacto")}</small>
          </div>
        </td>
        <td><span class="club-pill club-pill--small">${escapeHtml(clubLabels[client.club_type] || "Club")}</span></td>
        <td><strong>${escapeHtml(client.client_code)}</strong></td>
        <td><strong>${formatNumber(client.points)}</strong></td>
        <td><span class="status-badge ${client.is_active ? "is-active" : "is-inactive"}">${client.is_active ? "Activo" : "Inactivo"}</span></td>
        <td>
          <div class="table-actions">
            <button class="table-button" type="button" data-client-action="open" data-client-id="${client.id}">Abrir</button>
            <button class="table-button" type="button" data-client-action="copy" data-client-id="${client.id}">Copiar link</button>
          </div>
        </td>
      </tr>
    `).join("");
  }

  function renderRecentClients() {
    const recent = state.clients.slice(0, 6);
    $("recentClients").innerHTML = recent.length ? recent.map((client) => `
      <button class="compact-item text-button" type="button" data-open-client="${client.id}">
        <span class="compact-item__main">
          <strong>${escapeHtml(client.full_name)}</strong>
          <small>${escapeHtml(clubLabels[client.club_type] || "Club")} · ${formatNumber(client.points)} puntos</small>
        </span>
        <span class="status-badge ${client.is_active ? "is-active" : "is-inactive"}">${client.is_active ? "Activo" : "Inactivo"}</span>
      </button>
    `).join("") : '<div class="empty-state">Todavía no hay clientes.</div>';
  }

  async function loadRules() {
    const { data, error } = await db.rpc("admin_get_reward_rules");
    if (error) throw error;
    state.rules = Array.isArray(data) ? data : [];
    renderRules();
  }

  function renderRules() {
    const order = ["vapers", "jerseys", "perfumes", "importb2b"];
    $("rulesGrid").innerHTML = order.map((clubType) => {
      const rules = state.rules.filter((rule) => rule.club_type === clubType);
      const extra = clubType === "importb2b"
        ? '<div class="rule-condition">Condición adicional: compra mínima de <strong>$30.000</strong>.</div>'
        : "";

      return `
        <article class="panel rule-card">
          <div class="rule-card__header">
            <div><span class="eyebrow">${escapeHtml(clubLabels[clubType])}</span><h2>${escapeHtml(clubLabels[clubType])}</h2></div>
            <span class="club-pill">+1 por validación</span>
          </div>
          <p>${escapeHtml(clubRules[clubType])}</p>
          ${extra}
          <div class="rule-milestones">
            ${rules.map((rule) => `
              <div class="rule-milestone">
                <strong>${rule.recurring_every ? `Cada ${formatNumber(rule.recurring_every)} puntos` : `${formatNumber(rule.milestone)} puntos`}</strong>
                <span>${escapeHtml(rule.reward_name)}</span>
                <small>${escapeHtml(rule.reward_description)}</small>
              </div>
            `).join("")}
          </div>
        </article>
      `;
    }).join("");
  }

  async function loadClaims() {
    const { data, error } = await db.rpc("admin_get_reward_claims", { p_status: null });
    if (error) throw error;
    state.claims = Array.isArray(data) ? data : [];
    renderClaims();
    renderPendingClaims();
  }

  function renderClaims() {
    const body = $("claimsTableBody");
    $("claimsEmpty").hidden = state.claims.length > 0;

    body.innerHTML = state.claims.map((claim) => `
      <tr>
        <td><strong>${escapeHtml(claim.client_name)}</strong><br><small>${escapeHtml(claim.client_code)}</small></td>
        <td><span class="club-pill club-pill--small">${escapeHtml(clubLabels[claim.club_type] || "Club")}</span></td>
        <td><strong>${escapeHtml(claim.reward_name)}</strong></td>
        <td>${formatNumber(claim.milestone)} puntos</td>
        <td><span class="status-badge ${claim.status === "delivered" ? "is-active" : "is-pending"}">${claim.status === "delivered" ? "Entregado" : "Pendiente"}</span></td>
        <td>${escapeHtml(formatDate(claim.unlocked_at, false))}</td>
        <td>
          <button class="table-button" type="button" data-claim-action="toggle" data-claim-id="${claim.id}">
            ${claim.status === "delivered" ? "Marcar pendiente" : "Marcar entregado"}
          </button>
        </td>
      </tr>
    `).join("");
  }

  function renderPendingClaims() {
    const pending = state.claims.filter((claim) => claim.status === "pending").slice(0, 6);
    $("pendingClaims").innerHTML = pending.length ? pending.map((claim) => `
      <button class="compact-item text-button" type="button" data-go-view="claims">
        <span class="compact-item__main">
          <strong>${escapeHtml(claim.client_name)}</strong>
          <small>${escapeHtml(claim.reward_name)} · ${formatNumber(claim.milestone)} puntos</small>
        </span>
        <span class="status-badge is-pending">Pendiente</span>
      </button>
    `).join("") : '<div class="empty-state">No hay premios pendientes.</div>';
  }

  function resetClientForm() {
    $("clientForm").reset();
    $("clientId").value = "";
    $("clientJoinedAt").value = getLocalDateInputValue();
    $("clientClub").value = "vapers";
    $("clientFormTitle").textContent = "Crear cliente";
    $("clientFormMessage").textContent = "";
  }

  function openCreateClient() {
    resetClientForm();
    $("clientDialog").showModal();
  }

  function openEditClient(client) {
    $("clientId").value = client.id;
    $("clientFullName").value = client.full_name || "";
    $("clientPhone").value = client.phone || "";
    $("clientInstagram").value = client.instagram_username ? `@${client.instagram_username}` : "";
    $("clientJoinedAt").value = client.joined_at || getLocalDateInputValue();
    $("clientClub").value = client.club_type || "importb2b";
    $("clientNotes").value = client.internal_notes || "";
    $("clientFormTitle").textContent = "Editar cliente";
    $("clientFormMessage").textContent = client.points > 0
      ? "El club no puede cambiarse porque este cliente ya tiene puntos registrados."
      : "";
    $("clientClub").disabled = client.points > 0;
    $("clientDialog").showModal();
  }

  async function saveClient(event) {
    event.preventDefault();
    const button = $("saveClientButton");
    const id = $("clientId").value;
    const fullName = $("clientFullName").value.trim();
    const phone = $("clientPhone").value.trim();
    const instagram = normalizeInstagram($("clientInstagram").value);
    const joinedAt = $("clientJoinedAt").value;
    const notes = $("clientNotes").value.trim();
    const clubType = $("clientClub").disabled
      ? state.clients.find((client) => client.id === id)?.club_type
      : $("clientClub").value;

    if (fullName.length < 2 || !joinedAt || !clubType) {
      $("clientFormMessage").textContent = "Completa nombre, club y fecha de ingreso.";
      return;
    }

    try {
      setButtonLoading(button, true, "Guardando...");
      const params = {
        p_full_name: fullName,
        p_phone: phone || null,
        p_instagram_username: instagram || null,
        p_joined_at: joinedAt,
        p_internal_notes: notes || null,
        p_club_type: clubType
      };

      const result = id
        ? await db.rpc("admin_update_client", { p_client_id: id, ...params })
        : await db.rpc("admin_create_client", params);

      if (result.error) throw result.error;
      $("clientDialog").close();
      $("clientClub").disabled = false;
      await Promise.all([loadClients($("clientSearch").value), loadStats()]);
      showToast(id ? "Cliente actualizado." : "Cliente creado. El alta inicia con 0 puntos.");
    } catch (error) {
      console.error(error);
      $("clientFormMessage").textContent = error.message || "No se pudo guardar el cliente.";
    } finally {
      setButtonLoading(button, false);
    }
  }

  function selectedClient() {
    return state.clients.find((client) => client.id === state.selectedClientId) || null;
  }

  async function openClient(clientId) {
    const client = state.clients.find((item) => item.id === clientId);
    if (!client) return;
    state.selectedClientId = clientId;
    renderClientDetail(client);
    $("clientDetailDialog").showModal();
    await loadClientHistory(clientId);
  }

  function renderClientDetail(client) {
    $("detailClientName").textContent = client.full_name;
    $("detailClientCode").textContent = client.client_code;
    $("detailClientStatus").textContent = client.is_active ? "Activo" : "Inactivo";
    $("detailClientStatus").className = `status-badge ${client.is_active ? "is-active" : "is-inactive"}`;
    $("detailClientClub").textContent = clubLabels[client.club_type] || "Club";
    $("detailClientContact").textContent = [
      client.phone,
      client.instagram_username ? `@${client.instagram_username}` : ""
    ].filter(Boolean).join(" · ") || "Sin contacto";
    $("detailPoints").textContent = formatNumber(client.points);
    $("detailValidActions").textContent = formatNumber(client.points);
    $("detailPendingRewards").textContent = formatNumber(
      state.claims.filter((claim) => claim.client_id === client.id && claim.status === "pending").length
    );
    $("toggleSelectedClient").textContent = client.is_active ? "Desactivar" : "Reactivar";
    $("actionClubRule").textContent = clubRules[client.club_type] || "";

    const amountField = $("purchaseAmountField");
    const amountInput = $("actionPurchaseAmount");
    const isImport = client.club_type === "importb2b";
    amountField.hidden = !isImport;
    amountInput.required = isImport;
    amountInput.value = "";
    $("actionObservation").value = "";
  }

  async function loadClientHistory(clientId) {
    $("adminClientHistory").innerHTML = '<div class="empty-state">Cargando historial...</div>';
    const { data, error } = await db.rpc("admin_get_client_history", { p_client_id: clientId });
    if (error) {
      console.error(error);
      $("adminClientHistory").innerHTML = '<div class="empty-state">No se pudo cargar el historial.</div>';
      return;
    }

    const history = Array.isArray(data) ? data : [];
    $("adminClientHistory").innerHTML = history.length ? history.map((item) => {
      const pointAdded = Number(item.metadata?.point_added || 0);
      const amount = item.metadata?.purchase_amount;
      const observation = item.metadata?.observation;
      return `
        <article class="history-item">
          <div class="history-dot" aria-hidden="true"></div>
          <div class="history-item__content">
            <div class="history-item__header">
              <strong>${escapeHtml(eventLabels[item.event_type] || "Movimiento")}</strong>
              ${pointAdded ? '<span class="point-change">+1 punto</span>' : ""}
            </div>
            <p>${escapeHtml(item.description)}</p>
            ${amount ? `<small class="history-extra">Monto: ${escapeHtml(formatMoney(amount))}</small>` : ""}
            ${observation ? `<small class="history-extra">${escapeHtml(observation)}</small>` : ""}
            <div class="history-item__meta">
              <time>${escapeHtml(formatDate(item.created_at, true))}</time>
              <span>${escapeHtml(item.admin_name || "Administrador")}</span>
            </div>
          </div>
        </article>
      `;
    }).join("") : '<div class="empty-state">Todavía no hay movimientos registrados.</div>';
  }

  async function registerVerifiedPurchase(event) {
    event.preventDefault();
    const client = selectedClient();
    if (!client) return;

    const button = $("saveActionButton");
    const rawAmount = $("actionPurchaseAmount").value.trim();
    const amount = rawAmount ? Number(rawAmount) : null;
    const observation = $("actionObservation").value.trim();

    if (client.club_type === "importb2b" && (!Number.isFinite(amount) || amount < 30000)) {
      showToast("Club IMPORTB2B requiere una compra mínima de $30.000.", "error");
      return;
    }

    try {
      setButtonLoading(button, true, "Registrando...");
      const { data, error } = await db.rpc("admin_register_verified_purchase", {
        p_client_id: client.id,
        p_purchase_amount: amount,
        p_observation: observation || null
      });
      if (error) throw error;

      await Promise.all([
        loadClients($("clientSearch").value),
        loadStats(),
        loadClaims()
      ]);

      const refreshed = state.clients.find((item) => item.id === client.id);
      if (refreshed) renderClientDetail(refreshed);
      await loadClientHistory(client.id);

      if (data?.reward_unlocked) {
        showToast(`+1 punto registrado. Premio desbloqueado: ${data.reward_unlocked}`);
      } else {
        showToast("Compra + historia verificadas. +1 punto registrado.");
      }
    } catch (error) {
      console.error(error);
      showToast(error.message || "No se pudo registrar el punto.", "error");
    } finally {
      setButtonLoading(button, false);
    }
  }

  async function copyClientLink(client) {
    if (!client?.access_token) return;
    const link = `${window.location.origin}/c/${encodeURIComponent(client.access_token)}`;
    try {
      await navigator.clipboard.writeText(link);
      showToast("Enlace privado copiado.");
    } catch (_) {
      window.prompt("Copia el enlace del cliente:", link);
    }
  }

  async function toggleClientStatus() {
    const client = selectedClient();
    if (!client) return;
    try {
      const { error } = await db.rpc("admin_set_client_status", {
        p_client_id: client.id,
        p_is_active: !client.is_active
      });
      if (error) throw error;
      await Promise.all([loadClients($("clientSearch").value), loadStats()]);
      const refreshed = state.clients.find((item) => item.id === client.id);
      if (refreshed) renderClientDetail(refreshed);
      await loadClientHistory(client.id);
      showToast(refreshed?.is_active ? "Cliente reactivado." : "Cliente desactivado.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No se pudo cambiar el estado.", "error");
    }
  }

  async function deleteClient() {
    const client = selectedClient();
    if (!client) return;
    if (!window.confirm(`¿Eliminar definitivamente a ${client.full_name}? Esta acción también elimina sus puntos y premios.`)) return;

    try {
      const { error } = await db.rpc("admin_delete_client", { p_client_id: client.id });
      if (error) throw error;
      $("clientDetailDialog").close();
      state.selectedClientId = null;
      await Promise.all([loadClients($("clientSearch").value), loadStats(), loadClaims()]);
      showToast("Cliente eliminado.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No se pudo eliminar el cliente.", "error");
    }
  }

  async function toggleClaim(claimId) {
    const claim = state.claims.find((item) => item.id === claimId);
    if (!claim) return;
    const nextStatus = claim.status === "delivered" ? "pending" : "delivered";

    try {
      const { error } = await db.rpc("admin_update_reward_claim_status", {
        p_claim_id: claim.id,
        p_status: nextStatus,
        p_notes: claim.notes || null
      });
      if (error) throw error;
      await Promise.all([loadClaims(), loadStats()]);
      if (state.selectedClientId) {
        const client = selectedClient();
        if (client) renderClientDetail(client);
        await loadClientHistory(state.selectedClientId);
      }
      showToast(nextStatus === "delivered" ? "Premio marcado como entregado." : "Premio vuelto a pendiente.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No se pudo actualizar el premio.", "error");
    }
  }

  function bindEvents() {
    document.querySelectorAll(".nav-button").forEach((button) => {
      button.addEventListener("click", () => showView(button.dataset.view));
    });

    document.addEventListener("click", (event) => {
      const goView = event.target.closest("[data-go-view]");
      if (goView) showView(goView.dataset.goView);

      const openButton = event.target.closest("[data-open-client]");
      if (openButton) openClient(openButton.dataset.openClient);

      const clientButton = event.target.closest("[data-client-action]");
      if (clientButton) {
        const client = state.clients.find((item) => item.id === clientButton.dataset.clientId);
        if (!client) return;
        if (clientButton.dataset.clientAction === "open") openClient(client.id);
        if (clientButton.dataset.clientAction === "copy") copyClientLink(client);
      }

      const claimButton = event.target.closest("[data-claim-action]");
      if (claimButton?.dataset.claimAction === "toggle") toggleClaim(claimButton.dataset.claimId);

      const closeButton = event.target.closest("[data-close-dialog]");
      if (closeButton) {
        const dialog = $(closeButton.dataset.closeDialog);
        if (dialog?.open) dialog.close();
        if (dialog?.id === "clientDialog") $("clientClub").disabled = false;
      }
    });

    $("quickCreateButton").addEventListener("click", openCreateClient);
    $("createClientButton").addEventListener("click", openCreateClient);
    $("clientForm").addEventListener("submit", saveClient);
    $("actionForm").addEventListener("submit", registerVerifiedPurchase);

    $("copyClientLink").addEventListener("click", () => copyClientLink(selectedClient()));
    $("editSelectedClient").addEventListener("click", () => {
      const client = selectedClient();
      if (!client) return;
      $("clientDetailDialog").close();
      openEditClient(client);
    });
    $("toggleSelectedClient").addEventListener("click", toggleClientStatus);
    $("deleteSelectedClient").addEventListener("click", deleteClient);

    $("clientSearch").addEventListener("input", () => {
      window.clearTimeout(state.searchTimer);
      state.searchTimer = window.setTimeout(async () => {
        try {
          await loadClients($("clientSearch").value);
        } catch (error) {
          console.error(error);
          showToast("No se pudo realizar la búsqueda.", "error");
        }
      }, 250);
    });

    $("clientInstagram").addEventListener("blur", () => {
      const normalized = normalizeInstagram($("clientInstagram").value);
      $("clientInstagram").value = normalized ? `@${normalized}` : "";
    });

    $("menuButton").addEventListener("click", () => {
      const sidebar = document.querySelector(".admin-sidebar");
      const open = sidebar.classList.toggle("is-open");
      $("menuButton").setAttribute("aria-expanded", String(open));
    });

    $("logoutButton").addEventListener("click", async () => {
      await db.auth.signOut();
      window.location.replace("/admin/login");
    });
  }

  async function init() {
    try {
      const allowed = await ensureAdminAccess();
      if (!allowed) return;

      $("adminName").textContent = state.admin.full_name;
      $("adminEmail").textContent = state.user.email || "—";
      $("adminInitials").textContent = getInitials(state.admin.full_name);

      bindEvents();
      await Promise.all([loadStats(), loadClients(""), loadRules(), loadClaims()]);

      $("adminLoading").hidden = true;
      $("adminApp").hidden = false;
    } catch (error) {
      console.error(error);
      $("adminLoading").innerHTML = `
        <strong>No pudimos cargar el panel</strong>
        <span>${escapeHtml(error.message || "Error inesperado")}</span>
        <button class="button button--ghost" type="button" onclick="location.reload()">Reintentar</button>
      `;
    }
  }

  init();
})();
