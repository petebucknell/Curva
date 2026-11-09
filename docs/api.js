// Calls one of the database functions in supabase/schema-v2.sql through Supabase's REST endpoint.
async function callFunction(name, body) {
  const { url, anonKey } = window.CURVA_CONFIG;
  if (url.includes("YOUR-PROJECT") || anonKey.includes("YOUR-ANON-KEY")) {
    throw new Error(
      `Could not run "${name}": Supabase is not configured. Set url and anonKey in docs/config.js. [CURVA_CONFIG_MISSING]`
    );
  }

  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const problem = await response.json().catch(() => ({}));
    throw new Error(problem.message || `Request failed (${response.status})`);
  }
  return response.json();
}
