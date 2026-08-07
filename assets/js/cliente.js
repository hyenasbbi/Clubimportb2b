(function clientCardPage() {
  "use strict";

  const loadingState = document.getElementById("loadingState");
  const errorState = document.getElementById("errorState");
  const errorMessage = document.getElementById("errorMessage");
  const cardContent = document.getElementById("cardContent");

  const eventLabels = {
    client_created: "Ingreso al club",
    verified_purchase_story: "Compra + historia verificada",
    reward_unlocked: "Premio desbloqueado",
    reward_delivered: "Premio entregado",
    status_change: "Cambio de estado",
    purchase: "Compra (registro anterior)",
    instagram_story: "Historia (registro anterior)",
    other: "Movimiento"
  };

  function getTokenFromUrl() {
    const parts = window.location.pathname.split("/").filter(Boolean);
    const cIndex = parts.indexOf("c");
    if (cIndex !== -1 && parts[cIndex + 1]) {
      return decodeURIComponent(parts[cIndex + 1]).trim();
    }
    return new URLSearchParams(window.location.search).get("token")?.trim() || "";
  }

  function formatDate(value, includeTime) {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    return new Intl.DateTimeFormat("es-AR", {
      dateStyle: "medium",
      ...(includeTime ? { timeStyle: "short" } : {})
    }).format(date);
  }

  function formatMoney(value) {
    if (value === null || value === undefined || value === "") return "";
    return new Intl.NumberFormat("es-AR", {
      style: "currency",
      currency: "ARS",
      maximumFractionDigits: 0
    }).format(Number(value));
  }

  function text(id, value) {
    const element = document.getElementById(id);
    if (element) element.textContent = value ?? "—";
  }

  function showError(message) {
    loadingState.hidden = true;
    cardContent.hidden = true;
    errorMessage.textContent = message;
    errorState.hidden = false;
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function pluralPoints(value) {
    const number = Number(value || 0);
    return `${number} ${number === 1 ? "punto" : "puntos"}`;
  }

  function renderRewards(data) {
    const container = document.getElementById("rewardsList");
    const rewards = Array.isArray(data.rewards) ? data.rewards : [];

    if (!rewards.length) {
      container.innerHTML = '<div class="empty-state">Todavía no hay recompensas configuradas para este club.</div>';
      return;
    }

    container.innerHTML = rewards.map((reward) => {
      const status = reward.status || "locked";
      const cardClass = status === "delivered" ? "is-delivered" : status === "unlocked" ? "is-unlocked" : "is-locked";
      const statusLabel = status === "delivered"
        ? "Entregado"
        : status === "unlocked"
          ? "Desbloqueado"
          : `Te faltan ${reward.remaining} ${Number(reward.remaining) === 1 ? "punto" : "puntos"}`;
      const icon = status === "delivered" ? "✓" : status === "unlocked" ? "★" : "🔒";

      return `
        <article class="reward-card ${cardClass}">
          <div class="reward-icon" aria-hidden="true">${icon}</div>
          <div>
            <div class="reward-card__topline">
              <h3>${escapeHtml(reward.reward_name)}</h3>
              <span>${escapeHtml(statusLabel)}</span>
            </div>
            <p>${escapeHtml(reward.description)}</p>
            <small>Meta: ${escapeHtml(pluralPoints(reward.milestone))}</small>
          </div>
        </article>
      `;
    }).join("");
  }

  function renderHistory(data) {
    const container = document.getElementById("historyList");
    const history = Array.isArray(data.history) ? data.history : [];

    if (!history.length) {
      container.innerHTML = '<div class="empty-state">Todavía no hay movimientos registrados.</div>';
      return;
    }

    container.innerHTML = history.map((item) => {
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
            ${amount ? `<small class="history-extra">Compra: ${escapeHtml(formatMoney(amount))}</small>` : ""}
            ${observation ? `<small class="history-extra">${escapeHtml(observation)}</small>` : ""}
            <div class="history-item__meta">
              <time>${escapeHtml(formatDate(item.created_at, true))}</time>
            </div>
          </div>
        </article>
      `;
    }).join("");
  }

  function renderCard(data) {
    const client = data.client;
    const isActive = Boolean(client.is_active);
    const statusBadge = document.getElementById("clientStatus");
    const progressBar = document.getElementById("progressBar");
    const progress = Math.max(0, Math.min(100, Number(data.progress_percent || 0)));

    text("clientName", client.full_name);
    text("clientCode", client.client_code);
    text("joinedAt", formatDate(`${client.joined_at}T12:00:00`, false));
    text("clubName", String(client.club_name || "Club IMPORTB2B").toUpperCase());
    text("pointsBalance", client.points);
    text("validActions", data.valid_actions);
    text("unlockedRewards", data.unlocked_rewards_count);
    text("deliveredRewards", data.delivered_rewards_count);
    text("progressPercent", `${progress}%`);

    statusBadge.textContent = isActive ? "Miembro activo" : "Miembro inactivo";
    statusBadge.className = `status-badge ${isActive ? "is-active" : "is-inactive"}`;
    progressBar.style.width = `${progress}%`;
    progressBar.parentElement.setAttribute("aria-valuenow", String(progress));

    if (data.next_reward) {
      text("nextRewardName", data.next_reward.name);
      text("nextRewardProgress", `${client.points} / ${data.next_reward.milestone} puntos`);
      text("nextRewardDescription", data.next_reward.description || "");
      const missing = Number(data.next_reward.remaining || 0);
      text("remainingPoints", `Te faltan ${missing} ${missing === 1 ? "punto" : "puntos"}`);
    } else {
      text("nextRewardName", "Beneficios actuales completados");
      text("nextRewardProgress", `${client.points} puntos acumulados`);
      text("nextRewardDescription", "Ya alcanzaste todas las recompensas definidas actualmente para este club.");
      text("remainingPoints", "Nuevos beneficios podrán sumarse próximamente");
    }

    renderRewards(data);
    renderHistory(data);

    loadingState.hidden = true;
    errorState.hidden = true;
    cardContent.hidden = false;
  }

  async function loadCard() {
    const token = getTokenFromUrl();

    if (!window.CLUB_CONFIG_READY) {
      showError("El sitio todavía no está conectado con Supabase. Revisa la configuración del proyecto.");
      return;
    }

    if (!token) {
      showError("Este enlace no contiene un token de cliente válido.");
      return;
    }

    try {
      const { data, error } = await window.clubSupabase.rpc("get_client_card_by_token", { p_token: token });
      if (error) throw error;
      if (!data || !data.client) {
        showError("No encontramos una tarjeta asociada a este enlace. Verifica que la URL esté completa.");
        return;
      }
      renderCard(data);
    } catch (error) {
      console.error(error);
      showError("No fue posible cargar la tarjeta. Inténtalo nuevamente más tarde.");
    }
  }

  loadCard();
})();
