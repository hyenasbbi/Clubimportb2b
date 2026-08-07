(function clientCardPage() {
  "use strict";

  const loadingState = document.getElementById("loadingState");
  const errorState = document.getElementById("errorState");
  const errorMessage = document.getElementById("errorMessage");
  const cardContent = document.getElementById("cardContent");

  const eventLabels = {
    client_created: "Ingreso al club",
    client_updated: "Actualización",
    purchase: "Compra",
    instagram_story: "Historia de Instagram",
    referral: "Referido",
    manual_adjustment: "Ajuste de créditos",
    reward_redemption: "Canje de recompensa",
    reward_reversal: "Reintegro de canje",
    status_change: "Cambio de estado",
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

  function renderRewards(data) {
    const container = document.getElementById("rewardsList");
    const rewards = Array.isArray(data.rewards) ? data.rewards : [];

    if (!rewards.length) {
      container.innerHTML = '<div class="empty-state">Todavía no hay recompensas activas.</div>';
      return;
    }

    container.innerHTML = rewards.map((reward) => {
      const availabilityClass = reward.is_available ? "is-unlocked" : "is-locked";
      const status = reward.is_available ? "Disponible" : `${reward.credits_required} créditos`;
      const stock = reward.stock === null ? "Stock ilimitado" : `${reward.stock} disponibles`;
      return `
        <article class="reward-card ${availabilityClass}">
          <div class="reward-icon" aria-hidden="true">${reward.is_available ? "✓" : "◆"}</div>
          <div>
            <div class="reward-card__topline">
              <h3>${escapeHtml(reward.name)}</h3>
              <span>${escapeHtml(status)}</span>
            </div>
            <p>${escapeHtml(reward.description)}</p>
            <small>${escapeHtml(stock)}</small>
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
              ${item.balance_after !== null && item.balance_after !== undefined ? `<span>Saldo: ${escapeHtml(String(item.balance_after))}</span>` : ""}
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
    text("purchaseCount", client.purchase_count);
    text("storyCount", client.instagram_story_count);
    text("referralCount", client.referral_count);
    text("creditBalance", client.credit_balance);
    text("progressPercent", `${progress}%`);

    statusBadge.textContent = isActive ? "Miembro activo" : "Miembro inactivo";
    statusBadge.className = `status-badge ${isActive ? "is-active" : "is-inactive"}`;
    progressBar.style.width = `${progress}%`;
    progressBar.setAttribute("aria-valuenow", String(progress));

    if (data.next_reward) {
      text("nextRewardName", data.next_reward.name);
      text("nextRewardCredits", `${data.next_reward.credits_required} créditos`);
      const missing = Math.max(0, data.next_reward.credits_required - client.credit_balance);
      text("remainingCredits", `Te faltan ${missing} créditos`);
    } else {
      text("nextRewardName", "Máximo nivel alcanzado");
      text("nextRewardCredits", "Todas las recompensas desbloqueadas");
      text("remainingCredits", "Tu progreso está completo");
    }

    renderRewards(data);
    renderHistory(data);

    loadingState.hidden = true;
    errorState.hidden = true;
    cardContent.hidden = false;
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
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
      const { data, error } = await window.clubSupabase.rpc("get_client_card_by_token", {
        p_token: token
      });

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
