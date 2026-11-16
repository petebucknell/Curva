// Fill these in from Supabase: Project Settings > API.
// The anon key is designed to be public. Row-level security and the database functions
// in supabase/ are what protect the data, not keeping this key secret.
window.CURVA_CONFIG = {
  url: "https://hkhzgxzebciutavcwfvx.supabase.co",
  anonKey: "sb_publishable_x_o4VKujUDio6gdwFpbwaw_ur0ew441",
  // On: trips are created by signed-in people with a profile, and friends sign up through the
  // invitation card. Old link-only trips keep working by link. Set to false to switch it off.
  requireSignIn: true,
};
