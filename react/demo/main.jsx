import React from "react";
import { createRoot } from "react-dom/client";

import {
  createLeaderboardClient,
  Leaderboard,
} from "../src/index.js";

const client = createLeaderboardClient({
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL,
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
  namespace: "example-game",
  countryCodeResolver: async () => "CA",
});

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <Leaderboard client={client} />
  </React.StrictMode>,
);
