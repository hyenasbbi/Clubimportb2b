(function adminPanel() {
  "use strict";

  const db = window.clubSupabase;
  const state = {
    user: null,
    admin: null,
    stats: {},
    clients: [],
    rewards: [],
    redemptions: [],
    selectedClientId: null,
    toastTimer: null
  };

  const viewTitles = {
    dashboard: "Resumen general",
    clients: "Gestión de clientes",
    rewards: "Recompensas del club",
    redemptions: "Gestión de canjes"
  };

  const statDefinitions = [
    ["clients_total", "Clientes totales", "Base completa"],
    ["clients_active", "Clientes activos", "Miembros habilitados"],
    ["purchases_total", "Compras registradas", "Actividad acumulada"],
    ["stories_total", "Historias etiquetadas", "Actividad acumulada"],
    ["referrals_total", "Referidos", "Actividad acumulada"],
    ["credits_in_circulation", "Créditos en circulación", "Saldo total"],
    ["credits_spent", "Créditos utilizados", "Canjes y descuentos"],
    ["redemptions_pending", "Canjes pendientes", "Requieren seguimiento"]
  ];

  const eventLabels = {
    client_created: "Ingreso al club",
    client_updated: "Actualización de datos",
    purchase: "Compra",
    instagram_story: "Historia de Instagram",
    referral: "Referido",
    manual_adjustment: "Ajuste manual",
    reward_redemption: "Canje de recompensa",
    reward_reversal: "Reintegro de canje",
    status_change: "Cambio de estado",
    other: "Otro movimiento"
  };

  const statusLabels = {
    pending: "Pendiente",
    approved: "Aprobado",
    delivered: "Entregado",
    cancelled: "Cancelado"
  };

  const $ = (id) => document.getElementById(id);

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
    }, 3600);
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
    $("menuButton").setAttribute("aria-expanded", "false");
  }

  async function ensureAdminAccess() {
    if (!window.CLUB_CONFIG_READY || !db) {
      $("adminLoading").innerHTML = `
        <strong>Falta configurar Supabase</strong>
        <span>Edita assets/js/config.example.js y vuelve a publicar.</span>
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
    renderStats();
  }

  function renderStats() {
    $("statsGrid").innerHTML = statDefinitions.map(([key, label, note]) => `
      <article class="stat-card">
        <small>${escapeHtml(label)}</small>
        <strong>${formatNumber(state.stats[key])}</strong>
        <span>${escapeHtml(note)}</span>
      </article>
    `).join("");
  }

  async function loadClients(query) {
    const { data, error } = await db.rpc("admin_search_clients", {
      p_query: query || ""
    });
    if (error) throw error;
    state.clients = Array.isArray(data) ? data : [];
    renderClientsTable();
    renderRecentClients();
    populateClientSelect();
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
        <td><strong>${escapeHtml(client.client_code)}</strong></td>
        <td>
          <div class="activity-pills">
            <span>${formatNumber(client.purchase_count)} compras</span>
            <span>${formatNumber(client.instagram_story_count)} historias</span>
            <span>${formatNumber(client.referral_count)} referidos</span>
          </div>
        </td>
        <td><strong>${formatNumber(client.credit_balance)}</strong></td>
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
          <small>${escapeHtml(client.client_code)} · ${formatDate(`${client.joined_at}T12:00:00`, false)}</small>
        </span>
        <span class="status-badge ${client.is_active ? "is-active" : "is-inactive"}">${client.is_active ? "Activo" : "Inactivo"}</span>
      </button>
    `).join("") : '<div class="empty-state">Todavía no hay clientes.</div>';
  }

  async function loadRewards() {
    const { data, error } = await db
      .from("rewards")
      .select("id, name, description, credits_required, stock, display_order, is_active, created_at, updated_at")
      .order("display_order", { ascending: true })
      .order("credits_required", { ascending: true });

    if (error) throw error;
    state.rewards = Array.isArray(data) ? data : [];
    renderAdminRewards();
    populateRewardSelect();
  }

  function renderAdminRewards() {
    const container = $("adminRewardsList");
    if (!state.rewards.length) {
      container.innerHTML = '<div class="empty-state">Todavía no hay recompensas creadas.</div>';
      return;
    }

    container.innerHTML = state.rewards.map((reward) => `
      <article class="admin-reward-item">
        <div class="admin-reward-item__top">
          <div>
            <h3>${escapeHtml(reward.name)}</h3>
            <span class="status-badge ${reward.is_active ? "is-active" : "is-inactive"}">${reward.is_active ? "Activa" : "Inactiva"}</span>
          </div>
          <strong>${formatNumber(reward.credits_required)} créditos</strong>
        </div>
        <p>${escapeHtml(reward.description)}</p>
        <div class="admin-reward-item__meta">
          <span>${reward.stock === null ? "Stock ilimitado" : `Stock: ${formatNumber(reward.stock)}`}</span>
          <span>Orden: ${formatNumber(reward.display_order)}</span>
        </div>
        <div class="admin-reward-item__actions">
          <button class="table-button" type="button" data-reward-action="edit" data-reward-id="${reward.id}">Editar</button>
          <button class="table-button" type="button" data-reward-action="toggle" data-reward-id="${reward.id}">${reward.is_active ? "Desactivar" : "Activar"}</button>
        </div>
      </article>
    `).join("");
  }

  async function loadRedemptions() {
    const { data, error } = await db
      .from("reward_redemptions")
      .select("id, credits_spent, status, notes, redeemed_at, clients(full_name, client_code), rewards(name)")
      .order("redeemed_at", { ascending: false });

    if (error) throw error;
    state.redemptions = Array.isArray(data) ? data : [];
    renderRedemptions();
    renderPendingRedemptions();
  }

  function relationObject(value) {
    if (Array.isArray(value)) return value[0] || {};
    return value || {};
  }

  function renderRedemptions() {
    const body = $("redemptionsTableBody");
    $("redemptionsEmpty").hidden = state.redemptions.length > 0;

    body.innerHTML = state.redemptions.map((redemption) => {
      const client = relationObject(redemption.clients);
      const reward = relationObject(redemption.rewards);
      return `
        <tr>
          <td><div class="table-client"><strong>${escapeHtml(client.full_name || "Cliente eliminado")}</strong><small>${escapeHtml(client.client_code || "—")}</small></div></td>
          <td>${escapeHtml(reward.name || "Recompensa")}</td>
          <td>${formatNumber(redemption.credits_spent)}</td>
          <td>${escapeHtml(formatDate(redemption.redeemed_at, true))}</td>
          <td>
            <select id="redemption-status-${redemption.id}" ${redemption.status === "cancelled" ? "disabled" : ""}>
              ${Object.entries(statusLabels).map(([value, label]) => `<option value="${value}" ${redemption.status === value ? "selected" : ""}>${label}</option>`).join("")}
            </select>
          </td>
          <td><button class="table-button" type="button" data-redemption-action="save" data-redemption-id="${redemption.id}" ${redemption.status === "cancelled" ? "disabled" : ""}>Guardar</button></td>
        </tr>
      `;
    }).join("");
  }

  function renderPendingRedemptions() {
    const pending = state.redemptions.filter((item) => item.status === "pending").slice(0, 6);
    $("pendingRedemptions").innerHTML = pending.length ? pending.map((item) => {
      const client = relationObject(item.clients);
      const reward = relationObject(item.rewards);
      return `
        <div class="compact-item">
          <span class="compact-item__main">
            <strong>${escapeHtml(client.full_name || "Cliente")}</strong>
            <small>${escapeHtml(reward.name || "Recompensa")} · ${formatNumber(item.credits_spent)} créditos</small>
          </span>
          <span class="status-badge is-inactive">Pendiente</span>
        </div>
      `;
    }).join("") : '<div class="empty-state">No hay canjes pendientes.</div>';
  }

  function populateClientSelect() {
    const select = $("redemptionClient");
    const currentValue = select.value;
    select.innerHTML = '<option value="">Seleccionar cliente</option>' + state.clients
      .filter((client) => client.is_active)
      .map((client) => `<option value="${client.id}">${escapeHtml(client.full_name)} · ${escapeHtml(client.client_code)} · ${formatNumber(client.credit_balance)} créditos</option>`)
      .join("");
    select.value = currentValue;
  }

  function populateRewardSelect() {
    const select = $("redemptionReward");
    const currentValue = select.value;
    select.innerHTML = '<option value="">Seleccionar recompensa</option>' + state.rewards
      .filter((reward) => reward.is_active && (reward.stock === null || reward.stock > 0))
      .map((reward) => `<option value="${reward.id}">${escapeHtml(reward.name)} · ${formatNumber(reward.credits_required)} créditos</option>`)
      .join("");
    select.value = currentValue;
  }

  async function loadAll() {
    await Promise.all([
      loadStats(),
      loadClients(""),
      loadRewards(),
      loadRedemptions()
    ]);
  }

  function openClientForm(client) {
    $("clientForm").reset();
    $("clientFormMessage").textContent = "";
    $("clientFormMessage").className = "form-message";
    $("clientId").value = client?.id || "";
    $("clientFullName").value = client?.full_name || "";
    $("clientPhone").value = client?.phone || "";
    $("clientInstagram").value = client?.instagram_username ? `@${client.instagram_username}` : "";
    $("clientJoinedAt").value = client?.joined_at || new Date().toISOString().slice(0, 10);
    $("clientNotes").value = client?.internal_notes || "";
    $("clientFormTitle").textContent = client ? "Editar cliente" : "Crear cliente";
    $("saveClientButton").textContent = client ? "Guardar cambios" : "Crear cliente";
    $("clientDialog").showModal();
    window.setTimeout(() => $("clientFullName").focus(), 50);
  }

  async function saveClient(event) {
    event.preventDefault();
    const button = $("saveClientButton");
    const id = $("clientId").value;
    const fullName = $("clientFullName").value.trim();
    const phone = $("clientPhone").value.trim();
    const instagram = $("clientInstagram").value.trim();
    const joinedAt = $("clientJoinedAt").value;
    const notes = $("clientNotes").value.trim();

    if (fullName.length < 2 || !joinedAt) {
      $("clientFormMessage").textContent = "Completa el nombre y la fecha de ingreso.";
      $("clientFormMessage").className = "form-message is-error";
      return;
    }

    setButtonLoading(button, true, id ? "Guardando..." : "Creando...");

    try {
      const functionName = id ? "admin_update_client" : "admin_create_client";
      const params = id ? {
        p_client_id: id,
        p_full_name: fullName,
        p_phone: phone || null,
        p_instagram_username: instagram || null,
        p_joined_at: joinedAt,
        p_internal_notes: notes || null
      } : {
        p_full_name: fullName,
        p_phone: phone || null,
        p_instagram_username: instagram || null,
        p_joined_at: joinedAt,
        p_internal_notes: notes || null
      };

      const { data, error } = await db.rpc(functionName, params);
      if (error) throw error;

      $("clientDialog").close();
      await Promise.all([loadClients($("clientSearch").value.trim()), loadStats()]);
      showToast(id ? "Cliente actualizado correctamente." : "Cliente creado correctamente.");

      if (!id && data?.id) {
        state.selectedClientId = data.id;
        await openClientDetail(data.id);
      } else if (id && state.selectedClientId === id) {
        await openClientDetail(id, false);
      }
    } catch (error) {
      console.error(error);
      $("clientFormMessage").textContent = error.message || "No fue posible guardar el cliente.";
      $("clientFormMessage").className = "form-message is-error";
    } finally {
      setButtonLoading(button, false);
    }
  }

  function selectedClient() {
    return state.clients.find((client) => client.id === state.selectedClientId) || null;
  }

  async function openClientDetail(clientId, showDialog = true) {
    state.selectedClientId = clientId;
    const client = selectedClient();
    if (!client) {
      showToast("No se encontró el cliente.", "error");
      return;
    }

    renderClientDetail(client);
    if (showDialog && !$("clientDetailDialog").open) $("clientDetailDialog").showModal();
    await loadClientHistory(clientId);
  }

  function renderClientDetail(client) {
    $("detailClientName").textContent = client.full_name;
    $("detailClientCode").textContent = client.client_code;
    $("detailClientContact").textContent = [client.phone, client.instagram_username ? `@${client.instagram_username}` : ""].filter(Boolean).join(" · ") || "Sin contacto";
    $("detailPurchases").textContent = formatNumber(client.purchase_count);
    $("detailStories").textContent = formatNumber(client.instagram_story_count);
    $("detailReferrals").textContent = formatNumber(client.referral_count);
    $("detailCredits").textContent = formatNumber(client.credit_balance);
    $("detailClientStatus").textContent = client.is_active ? "Activo" : "Inactivo";
    $("detailClientStatus").className = `status-badge ${client.is_active ? "is-active" : "is-inactive"}`;
    $("toggleSelectedClient").textContent = client.is_active ? "Desactivar" : "Reactivar";
    $("saveActionButton").disabled = !client.is_active;
  }

  async function loadClientHistory(clientId) {
    $("adminClientHistory").innerHTML = '<div class="empty-state">Cargando historial...</div>';
    const { data, error } = await db.rpc("admin_get_client_history", { p_client_id: clientId });
    if (error) {
      $("adminClientHistory").innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
      return;
    }

    const history = Array.isArray(data) ? data : [];
    $("adminClientHistory").innerHTML = history.length ? history.map((item) => {
      const amount = Number(item.credit_amount || 0);
      const amountClass = amount > 0 ? "is-positive" : amount < 0 ? "is-negative" : "is-neutral";
      const amountLabel = amount > 0 ? `+${amount}` : String(amount);
      return `
        <article class="history-item">
          <div class="history-dot" aria-hidden="true"></div>
          <div class="history-item__content">
            <div class="history-item__header">
              <strong>${escapeHtml(eventLabels[item.event_type] || "Movimiento")}</strong>
              ${amount !== 0 ? `<span class="credit-change ${amountClass}">${escapeHtml(amountLabel)} créditos</span>` : ""}
            </div>
            <p>${escapeHtml(item.description)}</p>
            <div class="history-item__meta">
              <time>${escapeHtml(formatDate(item.created_at, true))}</time>
              <span>${escapeHtml(item.admin_name || "Administrador")}${item.balance_after !== null && item.balance_after !== undefined ? ` · Saldo ${formatNumber(item.balance_after)}` : ""}</span>
            </div>
          </div>
        </article>
      `;
    }).join("") : '<div class="empty-state">Todavía no hay movimientos registrados.</div>';
  }

  async function saveAction(event) {
    event.preventDefault();
    const client = selectedClient();
    if (!client) return;

    const actionType = $("actionType").value;
    const credits = Number.parseInt($("actionCredits").value, 10);
    const reason = $("actionReason").value.trim();
    const button = $("saveActionButton");

    if (!Number.isInteger(credits) || reason.length < 2) {
      showToast("Indica una cantidad válida y el motivo.", "error");
      return;
    }

    setButtonLoading(button, true, "Registrando...");
    try {
      const { error } = await db.rpc("admin_register_action", {
        p_client_id: client.id,
        p_action_type: actionType,
        p_credit_amount: credits,
        p_reason: reason
      });
      if (error) throw error;

      $("actionForm").reset();
      $("actionCredits").value = "0";
      await Promise.all([loadClients($("clientSearch").value.trim()), loadStats()]);
      const refreshedClient = selectedClient();
      if (refreshedClient) renderClientDetail(refreshedClient);
      await loadClientHistory(client.id);
      showToast("Movimiento registrado correctamente.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible registrar el movimiento.", "error");
    } finally {
      setButtonLoading(button, false);
    }
  }

  async function toggleSelectedClient() {
    const client = selectedClient();
    if (!client) return;
    const nextStatus = !client.is_active;
    const verb = nextStatus ? "reactivar" : "desactivar";
    if (!window.confirm(`¿Confirmas que deseas ${verb} a ${client.full_name}?`)) return;

    try {
      const { error } = await db.rpc("admin_set_client_status", {
        p_client_id: client.id,
        p_is_active: nextStatus
      });
      if (error) throw error;
      await Promise.all([loadClients($("clientSearch").value.trim()), loadStats()]);
      const refreshedClient = selectedClient();
      if (refreshedClient) renderClientDetail(refreshedClient);
      await loadClientHistory(client.id);
      showToast(`Cliente ${nextStatus ? "reactivado" : "desactivado"}.`);
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible cambiar el estado.", "error");
    }
  }

  async function deleteSelectedClient() {
    const client = selectedClient();
    if (!client) return;
    const confirmation = window.confirm(
      `Vas a eliminar definitivamente a ${client.full_name}, junto con su historial y movimientos. Esta acción no se puede deshacer. ¿Continuar?`
    );
    if (!confirmation) return;

    try {
      const { error } = await db.rpc("admin_delete_client", { p_client_id: client.id });
      if (error) throw error;
      $("clientDetailDialog").close();
      state.selectedClientId = null;
      await Promise.all([loadClients($("clientSearch").value.trim()), loadStats(), loadRedemptions()]);
      showToast("Cliente eliminado definitivamente.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible eliminar el cliente.", "error");
    }
  }

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
  }

  async function copyClientLink(clientId) {
    const client = state.clients.find((item) => item.id === clientId);
    if (!client) return;
    try {
      await copyText(`${window.location.origin}/c/${client.access_token}`);
      showToast("Enlace privado copiado.");
    } catch (error) {
      console.error(error);
      showToast("No fue posible copiar el enlace.", "error");
    }
  }

  function resetRewardForm() {
    $("rewardForm").reset();
    $("rewardId").value = "";
    $("rewardOrder").value = "0";
    $("rewardActive").checked = true;
    $("rewardFormTitle").textContent = "Nueva recompensa";
    $("cancelRewardEdit").hidden = true;
  }

  function editReward(rewardId) {
    const reward = state.rewards.find((item) => item.id === rewardId);
    if (!reward) return;
    $("rewardId").value = reward.id;
    $("rewardName").value = reward.name;
    $("rewardDescription").value = reward.description;
    $("rewardCredits").value = reward.credits_required;
    $("rewardStock").value = reward.stock === null ? "" : reward.stock;
    $("rewardOrder").value = reward.display_order;
    $("rewardActive").checked = reward.is_active;
    $("rewardFormTitle").textContent = "Editar recompensa";
    $("cancelRewardEdit").hidden = false;
    $("rewardName").focus();
  }

  async function saveReward(event) {
    event.preventDefault();
    const id = $("rewardId").value;
    const name = $("rewardName").value.trim();
    const description = $("rewardDescription").value.trim();
    const credits = Number.parseInt($("rewardCredits").value, 10);
    const stockRaw = $("rewardStock").value.trim();
    const stock = stockRaw === "" ? null : Number.parseInt(stockRaw, 10);
    const order = Number.parseInt($("rewardOrder").value || "0", 10);
    const isActive = $("rewardActive").checked;
    const submitButton = event.submitter;

    if (name.length < 2 || description.length < 2 || !Number.isInteger(credits) || credits <= 0 || (stock !== null && (!Number.isInteger(stock) || stock < 0))) {
      showToast("Revisa los datos de la recompensa.", "error");
      return;
    }

    setButtonLoading(submitButton, true, "Guardando...");
    const payload = {
      name,
      description,
      credits_required: credits,
      stock,
      display_order: Number.isInteger(order) && order >= 0 ? order : 0,
      is_active: isActive
    };

    try {
      let result;
      if (id) {
        result = await db.from("rewards").update(payload).eq("id", id);
      } else {
        result = await db.from("rewards").insert({ ...payload, created_by: state.user.id });
      }
      if (result.error) throw result.error;

      resetRewardForm();
      await Promise.all([loadRewards(), loadStats()]);
      showToast(id ? "Recompensa actualizada." : "Recompensa creada.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible guardar la recompensa.", "error");
    } finally {
      setButtonLoading(submitButton, false);
    }
  }

  async function toggleReward(rewardId) {
    const reward = state.rewards.find((item) => item.id === rewardId);
    if (!reward) return;
    try {
      const { error } = await db.from("rewards").update({ is_active: !reward.is_active }).eq("id", reward.id);
      if (error) throw error;
      await Promise.all([loadRewards(), loadStats()]);
      showToast(`Recompensa ${reward.is_active ? "desactivada" : "activada"}.`);
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible actualizar la recompensa.", "error");
    }
  }

  async function saveRedemption(event) {
    event.preventDefault();
    const clientId = $("redemptionClient").value;
    const rewardId = $("redemptionReward").value;
    const notes = $("redemptionNotes").value.trim();
    const button = event.submitter;

    if (!clientId || !rewardId) {
      showToast("Selecciona el cliente y la recompensa.", "error");
      return;
    }

    setButtonLoading(button, true, "Registrando...");
    try {
      const { error } = await db.rpc("admin_redeem_reward", {
        p_client_id: clientId,
        p_reward_id: rewardId,
        p_notes: notes || null
      });
      if (error) throw error;

      $("redemptionForm").reset();
      await Promise.all([loadClients(""), loadRewards(), loadRedemptions(), loadStats()]);
      showToast("Canje registrado y créditos descontados.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible registrar el canje.", "error");
    } finally {
      setButtonLoading(button, false);
    }
  }

  async function updateRedemptionStatus(redemptionId, button) {
    const select = $(`redemption-status-${redemptionId}`);
    const status = select?.value;
    if (!status) return;

    if (status === "cancelled" && !window.confirm("Al cancelar el canje se reintegrarán los créditos y el stock. ¿Continuar?")) {
      await loadRedemptions();
      return;
    }

    setButtonLoading(button, true, "Guardando...");
    try {
      const { error } = await db.rpc("admin_update_redemption_status", {
        p_redemption_id: redemptionId,
        p_status: status,
        p_notes: null
      });
      if (error) throw error;
      await Promise.all([loadRedemptions(), loadClients(""), loadRewards(), loadStats()]);
      showToast("Estado del canje actualizado.");
    } catch (error) {
      console.error(error);
      showToast(error.message || "No fue posible actualizar el canje.", "error");
    } finally {
      setButtonLoading(button, false);
    }
  }

  function bindEvents() {
    document.querySelectorAll(".nav-button").forEach((button) => {
      button.addEventListener("click", () => showView(button.dataset.view));
    });

    document.querySelectorAll("[data-go-view]").forEach((button) => {
      button.addEventListener("click", () => showView(button.dataset.goView));
    });

    $("menuButton").addEventListener("click", () => {
      const sidebar = document.querySelector(".admin-sidebar");
      const isOpen = sidebar.classList.toggle("is-open");
      $("menuButton").setAttribute("aria-expanded", String(isOpen));
    });

    $("quickCreateButton").addEventListener("click", () => openClientForm(null));
    $("createClientButton").addEventListener("click", () => openClientForm(null));
    $("clientForm").addEventListener("submit", saveClient);
    $("actionForm").addEventListener("submit", saveAction);
    $("rewardForm").addEventListener("submit", saveReward);
    $("redemptionForm").addEventListener("submit", saveRedemption);
    $("cancelRewardEdit").addEventListener("click", resetRewardForm);

    document.querySelectorAll("[data-close-dialog]").forEach((button) => {
      button.addEventListener("click", () => $(button.dataset.closeDialog)?.close());
    });

    [$("clientDialog"), $("clientDetailDialog")].forEach((dialog) => {
      dialog.addEventListener("click", (event) => {
        if (event.target === dialog) dialog.close();
      });
    });

    let searchTimer;
    $("clientSearch").addEventListener("input", () => {
      window.clearTimeout(searchTimer);
      searchTimer = window.setTimeout(async () => {
        try {
          await loadClients($("clientSearch").value.trim());
        } catch (error) {
          showToast(error.message || "Error al buscar clientes.", "error");
        }
      }, 280);
    });

    $("clientsTableBody").addEventListener("click", (event) => {
      const button = event.target.closest("[data-client-action]");
      if (!button) return;
      if (button.dataset.clientAction === "open") openClientDetail(button.dataset.clientId);
      if (button.dataset.clientAction === "copy") copyClientLink(button.dataset.clientId);
    });

    $("recentClients").addEventListener("click", (event) => {
      const button = event.target.closest("[data-open-client]");
      if (button) openClientDetail(button.dataset.openClient);
    });

    $("copyClientLink").addEventListener("click", () => copyClientLink(state.selectedClientId));
    $("editSelectedClient").addEventListener("click", () => {
      const client = selectedClient();
      if (client) openClientForm(client);
    });
    $("toggleSelectedClient").addEventListener("click", toggleSelectedClient);
    $("deleteSelectedClient").addEventListener("click", deleteSelectedClient);

    $("adminRewardsList").addEventListener("click", (event) => {
      const button = event.target.closest("[data-reward-action]");
      if (!button) return;
      if (button.dataset.rewardAction === "edit") editReward(button.dataset.rewardId);
      if (button.dataset.rewardAction === "toggle") toggleReward(button.dataset.rewardId);
    });

    $("redemptionsTableBody").addEventListener("click", (event) => {
      const button = event.target.closest("[data-redemption-action]");
      if (button?.dataset.redemptionAction === "save") {
        updateRedemptionStatus(button.dataset.redemptionId, button);
      }
    });

    $("logoutButton").addEventListener("click", async () => {
      await db.auth.signOut();
      window.location.replace("/admin/login");
    });

    db.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") window.location.replace("/admin/login");
    });
  }

  async function initialize() {
    try {
      const allowed = await ensureAdminAccess();
      if (!allowed) return;

      $("adminName").textContent = state.admin.full_name;
      $("adminEmail").textContent = state.user.email || "—";
      $("adminInitials").textContent = getInitials(state.admin.full_name);

      bindEvents();
      await loadAll();

      $("adminLoading").hidden = true;
      $("adminApp").hidden = false;
    } catch (error) {
      console.error(error);
      $("adminLoading").innerHTML = `
        <strong>No fue posible cargar el panel</strong>
        <span>${escapeHtml(error.message || "Error desconocido")}</span>
        <a class="button button--ghost" href="/admin/login">Volver al acceso</a>
      `;
    }
  }

  initialize();
})();
