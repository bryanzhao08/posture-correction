export interface Setup {
  sport: string; training: string | null; view: string;
  stroke: "forehand" | "backhand"; drill: string | null;
}
export interface Route {
  screen: "home" | "setup" | "live" | "summary" | "history" | "plans";
  setup?: Setup;
  source?: "camera" | "sample";
  id?: string;
}

export function routeHash(route: Route): string {
  const params = new URLSearchParams();
  if (route.setup) for (const [key, value] of Object.entries(route.setup)) if (value != null) params.set(key, value);
  if (route.source) params.set("source", route.source);
  if (route.id) params.set("id", route.id);
  return `#${route.screen}${params.size ? "?" + params : ""}`;
}

function readRoute(): Route {
  const [screen, query] = location.hash.slice(1).split("?");
  const p = new URLSearchParams(query);
  if (screen === "setup" || screen === "live") return {
    screen, source: screen === "live" ? (p.get("source") === "sample" ? "sample" : "camera") : undefined,
    setup: { sport: p.get("sport") ?? "golf", training: p.get("training"), view: p.get("view") ?? "front",
      stroke: p.get("stroke") === "backhand" ? "backhand" : "forehand", drill: p.get("drill") },
  };
  if (screen === "summary") return { screen, id: p.get("id") ?? undefined };
  return { screen: screen === "history" || screen === "plans" ? screen : "home" };
}

/** Hash URLs work on Pages. Entry positions allow browser Back to preserve a live session. */
export class Router {
  current: Route = readRoute();
  private index = 0;
  private restoring = false;
  onLeaveLive: (() => void) | null = null;
  constructor(private render: (route: Route) => void) {}

  start() {
    this.index = window.history.state?.fcIndex ?? 0;
    window.history.replaceState({ fcIndex: this.index }, "", routeHash(this.current));
    window.addEventListener("popstate", () => this.restore());
    window.addEventListener("hashchange", () => {
      if (!this.restoring && location.hash !== routeHash(this.current)) this.restore();
    });
    this.render(this.current);
  }

  navigate(route: Route, replace = false, allowExit = false) {
    if (this.onLeaveLive && !allowExit) { this.onLeaveLive(); return; }
    this.current = route;
    if (!replace) this.index++;
    window.history[replace ? "replaceState" : "pushState"]({ fcIndex: this.index }, "", routeHash(route));
    this.render(route);
  }

  /** Chip selection updates the setup entry without adding a Back step for every chip. */
  update(route: Route) {
    this.current = route;
    window.history.replaceState({ fcIndex: this.index }, "", routeHash(route));
  }

  private restore() {
    if (this.restoring) { this.restoring = false; return; }
    const index = window.history.state?.fcIndex;
    if (this.onLeaveLive) {
      if (typeof index === "number" && index !== this.index) {
        this.restoring = true;
        window.history.go(this.index - index);
      } else window.history.replaceState({ fcIndex: this.index }, "", routeHash(this.current));
      this.onLeaveLive();
      return;
    }
    this.index = typeof index === "number" ? index : this.index + 1;
    this.current = readRoute();
    window.history.replaceState({ fcIndex: this.index }, "", routeHash(this.current));
    this.render(this.current);
  }
}
