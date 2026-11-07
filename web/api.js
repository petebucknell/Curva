// Calls one of the database functions in supabase/schema.sql through Supabase's REST endpoint.
async function callFunction(name, body) {
  const { url, anonKey } = window.CURVA_CONFIG;
  if (url.includes("YOUR-PROJECT") || anonKey.includes("YOUR-ANON-KEY")) {
    throw new Error("Supabase is not configured yet. Fill in web/config.js.");
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
