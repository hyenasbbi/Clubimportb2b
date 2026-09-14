(function loginPage() {
  "use strict";

  const form = document.getElementById("loginForm");
  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");
  const submitButton = document.getElementById("loginButton");
  const message = document.getElementById("loginMessage");
  const configWarning = document.getElementById("configWarning");
  const togglePassword = document.getElementById("togglePassword");

  function showMessage(text, type) {
    message.textContent = text || "";
    message.className = "form-message";
    if (text) message.classList.add(type === "success" ? "is-success" : "is-error");
  }

  function setLoading(isLoading) {
    submitButton.disabled = isLoading;
    submitButton.textContent = isLoading ? "Ingresando..." : "Ingresar al panel";
  }

  async function verifyAdmin(userId) {
    const { data, error } = await window.clubSupabase
      .from("admins")
      .select("id, full_name, is_active")
      .eq("id", userId)
      .maybeSingle();

    if (error) throw error;
    return data && data.is_active ? data : null;
  }

  async function redirectIfAuthenticated() {
    if (!window.CLUB_CONFIG_READY) return;

    const { data, error } = await window.clubSupabase.auth.getUser();
    if (error || !data.user) return;

    try {
      const admin = await verifyAdmin(data.user.id);
      if (admin) window.location.replace("/admin");
    } catch (verificationError) {
      console.error(verificationError);
    }
  }

  if (!window.CLUB_CONFIG_READY) {
    configWarning.hidden = false;
    form.querySelectorAll("input, button").forEach((element) => {
      element.disabled = true;
    });
  } else {
    redirectIfAuthenticated();
  }

  togglePassword.addEventListener("click", function () {
    const isPassword = passwordInput.type === "password";
    passwordInput.type = isPassword ? "text" : "password";
    togglePassword.textContent = isPassword ? "Ocultar" : "Mostrar";
    togglePassword.setAttribute("aria-pressed", String(isPassword));
  });

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    showMessage("");

    if (!window.CLUB_CONFIG_READY) {
      showMessage("Primero debes configurar Supabase.", "error");
      return;
    }

    const email = emailInput.value.trim();
    const password = passwordInput.value;

    if (!email || !password) {
      showMessage("Completa el correo y la contraseña.", "error");
      return;
    }

    setLoading(true);

    try {
      const { data, error } = await window.clubSupabase.auth.signInWithPassword({
        email,
        password
      });

      if (error) throw error;

      const admin = await verifyAdmin(data.user.id);
      if (!admin) {
        await window.clubSupabase.auth.signOut();
        throw new Error("El usuario existe, pero no está habilitado como administrador del Club.");
      }

      showMessage("Acceso correcto. Abriendo el panel...", "success");
      window.location.replace("/admin");
    } catch (error) {
      console.error(error);
      showMessage(error.message || "No fue posible iniciar sesión.", "error");
    } finally {
      setLoading(false);
    }
  });
})();
