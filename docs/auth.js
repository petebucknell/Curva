// Email one-time-code sign-in through Supabase Auth's REST endpoints. No library.
// A person asks for a code, types the code from their email, and gets a session that
// the browser keeps. api.js sends that session with every database call.
const SESSION_KEY = "curva-session";
const EXPIRY_MARGIN_SECONDS = 60;

let refreshing = null;

async function authRequest(path, body, accessToken) {
  const { url, anonKey } = window.CURVA_CONFIG;
  const headers = { apikey: anonKey, "Content-Type": "application/json" };
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;

  const response = await fetch(`${url}/auth/v1/${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(data.msg || data.error_description || data.message || `Sign-in failed (${response.status})`);
    error.status = response.status;
    throw error;
  }
  return data;
}

function readSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_KEY));
  } catch {
    return null;
  }
}

function saveSession(data, email) {
  const session = {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_at: data.expires_at || Math.floor(Date.now() / 1000) + data.expires_in,
    email,
  };
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  return session;
}

function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

function emailFromToken(token) {
  try {
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload)).email || "";
  } catch {
    return "";
  }
}

// The sign-in link in the email sends the person back here with the session in the address.
// Keep it, then remove it from the address bar so it is not shared or bookmarked.
function captureSessionFromLink() {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const accessToken = params.get("access_token");
  const refreshToken = params.get("refresh_token");
  if (!accessToken || !refreshToken) return;
  saveSession(
    {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_at: Number(params.get("expires_at")) || 0,
      expires_in: Number(params.get("expires_in")) || 3600,
    },
    emailFromToken(accessToken)
  );
  history.replaceState(null, "", window.location.pathname + window.location.search);
}

// A refresh token can only be used once, so phones that refresh at the same moment share one request.
function refreshSession(session) {
  if (!refreshing) {
    refreshing = authRequest("token?grant_type=refresh_token", { refresh_token: session.refresh_token })
      .then((data) => saveSession(data, session.email))
      .catch((error) => {
        // Only a refusal ends the session. No signal on the road keeps the old one for next time.
        if ([400, 401, 403].includes(error.status)) {
          clearSession();
          return null;
        }
        return session;
      })
      .finally(() => {
        refreshing = null;
      });
  }
  return refreshing;
}

// The current session, renewed if it is about to expire. Null when signed out.
async function getSession() {
  const session = readSession();
  if (!session || !session.access_token) return null;
  if (session.expires_at - EXPIRY_MARGIN_SECONDS > Date.now() / 1000) return session;
  return refreshSession(session);
}

function cleanEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function friendlyAuthError(error) {
  if (error.status === 429) return "Too many codes requested. Wait a few minutes and try again.";
  return error.message;
}

async function requestCode(email) {
  const back = encodeURIComponent(window.location.origin + window.location.pathname + window.location.search);
  await authRequest(`otp?redirect_to=${back}`, { email: cleanEmail(email), create_user: true });
}

async function verifyCode(email, code) {
  const data = await authRequest("verify", {
    type: "email",
    email: cleanEmail(email),
    token: String(code).replace(/\s+/g, ""),
  });
  return saveSession(data, cleanEmail(email));
}

// Staging only. Lets a QA agent sign in without reading an email. It is off unless the config
// sets devPasswordSignIn, and it refuses to run against the live project whatever the config says.
const LIVE_PROJECT_HOST = "hkhzgxzebciutavcwfvx.supabase.co";

async function signInWithPassword(email, password) {
  const { url, devPasswordSignIn } = window.CURVA_CONFIG;
  if (!devPasswordSignIn || url.includes(LIVE_PROJECT_HOST)) {
    throw new Error("Test login is switched off here. [CURVA_DEV_LOGIN_OFF]");
  }
  const data = await authRequest("token?grant_type=password", { email: cleanEmail(email), password });
  return saveSession(data, cleanEmail(email));
}

async function signOut() {
  const session = readSession();
  clearSession();
  if (session && session.access_token) {
    // Best effort. The local session is already gone.
    authRequest("logout?scope=local", {}, session.access_token).catch(() => {});
  }
}

function signInRequired() {
  return Boolean(window.CURVA_CONFIG.requireSignIn);
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

// Builds the sign-in steps inside `container`. Calls onSignedIn(session) when the code works.
function mountSignIn(container, { message, onSignedIn }) {
  container.replaceChildren();

  const intro = element("p", "muted", message);
  const errorBox = element("p", "error");
  errorBox.setAttribute("role", "alert");
  errorBox.hidden = true;

  const emailLabel = element("label", "", "Email");
  emailLabel.htmlFor = "signin-email";
  const emailInput = element("input");
  emailInput.type = "text";
  emailInput.id = "signin-email";
  emailInput.setAttribute("inputmode", "email");
  emailInput.autocomplete = "email";
  emailInput.maxLength = 254;
  emailInput.placeholder = "you@example.com";
  const sendButton = element("button", "primary", "Email me a code");
  sendButton.type = "button";
  const emailRow = element("div", "row");
  emailRow.append(emailInput);
  const emailStep = element("div", "step");
  emailStep.append(emailLabel, emailRow, sendButton);

  const sentNote = element("p", "muted");
  const codeLabel = element("label", "", "Code from the email");
  codeLabel.htmlFor = "signin-code";
  const codeInput = element("input");
  codeInput.type = "text";
  codeInput.id = "signin-code";
  codeInput.setAttribute("inputmode", "numeric");
  codeInput.autocomplete = "one-time-code";
  codeInput.maxLength = 10;
  codeInput.placeholder = "123456";
  const verifyButton = element("button", "primary", "Sign in");
  verifyButton.type = "button";
  const backButton = element("button", "quiet", "Use a different email");
  backButton.type = "button";
  const codeRow = element("div", "row");
  codeRow.append(codeInput);
  const codeStep = element("div", "step");
  codeStep.hidden = true;
  codeStep.append(sentNote, codeLabel, codeRow, verifyButton, backButton);

  container.append(intro, emailStep, codeStep, errorBox);

  function showError(text) {
    errorBox.textContent = text;
    errorBox.hidden = false;
  }

  function clearError() {
    errorBox.textContent = "";
    errorBox.hidden = true;
  }

  async function send() {
    const email = cleanEmail(emailInput.value);
    if (!email.includes("@") || email.length < 5) {
      showError("Enter your email address.");
      emailInput.focus();
      return;
    }
    clearError();
    sendButton.disabled = true;
    try {
      await requestCode(email);
      sentNote.textContent = `We emailed ${email}. If the email has a code, type it below. If it has a sign-in link, open the link on this device. It can take a minute to arrive.`;
      emailStep.hidden = true;
      codeStep.hidden = false;
      codeInput.value = "";
      codeInput.focus();
    } catch (error) {
      showError(friendlyAuthError(error));
    } finally {
      sendButton.disabled = false;
    }
  }

  async function verify() {
    const code = codeInput.value.replace(/\s+/g, "");
    if (code.length < 4) {
      showError("Type the code from the email.");
      codeInput.focus();
      return;
    }
    clearError();
    verifyButton.disabled = true;
    try {
      const session = await verifyCode(cleanEmail(emailInput.value), code);
      onSignedIn(session);
    } catch (error) {
      showError(friendlyAuthError(error));
    } finally {
      verifyButton.disabled = false;
    }
  }

  sendButton.addEventListener("click", send);
  verifyButton.addEventListener("click", verify);
  backButton.addEventListener("click", () => {
    clearError();
    codeStep.hidden = true;
    emailStep.hidden = false;
    emailInput.focus();
  });
  emailInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      send();
    }
  });
  codeInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      verify();
    }
  });
}

// Shows who is signed in and a sign-out button. Hidden on the live site until sign-in is switched on.
async function renderAccountBar(container, onChange, onProfile) {
  const session = await getSession();
  container.replaceChildren();
  if (!session && !signInRequired()) return;
  if (!session) return;

  const who = element("span", "muted", session.email || "Signed in");
  const profileButton = element("button", "quiet", "Profile");
  profileButton.type = "button";
  if (onProfile) profileButton.addEventListener("click", onProfile);
  const out = element("button", "quiet", "Sign out");
  out.type = "button";
  out.addEventListener("click", async () => {
    await signOut();
    await renderAccountBar(container, onChange, onProfile);
    if (onChange) onChange();
  });
  container.append(who);
  if (onProfile) container.append(profileButton);
  container.append(out);
}

captureSessionFromLink();
