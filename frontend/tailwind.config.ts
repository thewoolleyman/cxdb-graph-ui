import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        "node-pending": "#e0e0e0",
        "node-running": "#90caf9",
        "node-complete": "#a5d6a7",
        "node-error": "#ef9a9a",
        "node-stale": "#ffcc80",
      },
      animation: {
        pulse: "pulse 1.5s infinite",
      },
    },
  },
  plugins: [],
};

export default config;
