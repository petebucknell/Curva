// Calls one of the database functions in supabase/schema-v2.sql and supabase/migrations
// through Supabase's REST endpoint. When someone is signed in, their session goes with the call.
async function callFunction(name, body) {
  const { url, anonKey } = window.CURVA_CONFIG;
  if (url.includes("YOUR-PROJECT") || anonKey.includes("YOUR-ANON-KEY")) {
    throw new Error(
      `Could not run "${name}": Supabase is not configured. Set url and anonKey in docs/config.js. [CURVA_CONFIG_MISSING]`
    );
  }

  const session = await getSession();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session ? session.access_token : anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (response.status === 401 && session) {
    clearSession();
    throw new Error(`Your sign-in has ended. Sign in again, then retry "${name}". [CURVA_SESSION_EXPIRED]`);
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => ({}));
    throw new Error(problem.message || `Request failed (${response.status})`);
  }
  return response.json();
}
