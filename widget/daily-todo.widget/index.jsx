import { css, run } from "uebersicht";

const PROJECT = "/Users/peilinwang/Desktop/pm-extra-credit";

export const command = `cat "${PROJECT}/data/today.json" 2>/dev/null || echo '{}'`;
export const refreshFrequency = 30 * 1000;

export const className = `
  top: 40px;
  right: 40px;
  width: 340px;
  font-family: -apple-system, "SF Pro Text", sans-serif;
  color: #f5f5f7;
`;

const card = css`
  background: rgba(28, 28, 30, 0.72);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border-radius: 18px;
  padding: 16px 18px;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.25);
`;
const header = css`
  display: flex; justify-content: space-between; align-items: baseline;
  margin-bottom: 4px;
`;
const h1 = css`font-size: 17px; font-weight: 700; margin: 0;`;
const h2 = css`
  font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em;
  color: #98989d; margin: 14px 0 6px;
`;
const summary = css`font-size: 12px; color: #c7c7cc; margin: 2px 0 0; line-height: 1.4;`;
const row = css`
  display: flex; gap: 10px; align-items: flex-start; padding: 6px 0;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  cursor: default;
`;
const dot = css`width: 8px; height: 8px; border-radius: 50%; margin-top: 5px; flex-shrink: 0;`;
const titleCss = css`font-size: 13px; line-height: 1.35;`;
const meta = css`font-size: 11px; color: #98989d; margin-top: 1px;`;
const button = css`
  font-size: 11px; color: #0a84ff; cursor: pointer; background: none; border: none; padding: 0;
`;
const footer = css`font-size: 10px; color: #6e6e73; margin-top: 12px;`;
const errorCss = css`font-size: 11px; color: #ff9f0a; margin-top: 8px;`;

const COLORS = { high: "#ff453a", medium: "#ffd60a", low: "#8e8e93" };
const SOURCE_LABEL = { canvas: "Canvas", calendar: "Calendar", gmail: "Email" };

const refresh = () =>
  run(`cd "${PROJECT}" && nohup /opt/homebrew/bin/python3 run.py >/dev/null 2>&1 &`);

const Item = ({ item }) => {
  const clickable = item.link && item.link.startsWith("http");
  return (
    <div
      className={row}
      style={{ cursor: clickable ? "pointer" : "default" }}
      onClick={() => clickable && run(`open "${item.link.replace(/"/g, "")}"`)}
    >
      <div className={dot} style={{ background: COLORS[item.priority] || COLORS.low }} />
      <div>
        <div className={titleCss}>{item.title}</div>
        <div className={meta}>
          {[item.time, (item.sources || []).map((s) => SOURCE_LABEL[s] || s).join(" · "), item.reason,
            item.confidence != null && `${Math.round(item.confidence * 100)}% sure`]
            .filter(Boolean)
            .join("  ·  ")}
        </div>
      </div>
    </div>
  );
};

const dayLabel = (iso) =>
  new Date(iso + "T12:00:00").toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });

export const render = ({ output }) => {
  let data = {};
  try { data = JSON.parse(output); } catch (e) {}

  const today = data.today || [];
  const upcoming = data.upcoming || [];
  const byDate = upcoming.reduce((acc, it) => ((acc[it.date] = acc[it.date] || []).push(it), acc), {});

  return (
    <div className={card}>
      <div className={header}>
        <h1 className={h1}>
          {new Date().toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })}
        </h1>
        <button className={button} onClick={refresh}>
          {data.status === "running" ? "Updating…" : "Refresh"}
        </button>
      </div>
      {data.summary && <p className={summary}>{data.summary}</p>}

      <div className={h2}>Today</div>
      {today.length ? today.map((it, i) => <Item key={i} item={it} />)
                    : <div className={meta}>Nothing yet — click Refresh.</div>}

      {Object.keys(byDate).sort().map((d) => (
        <div key={d}>
          <div className={h2}>{dayLabel(d)}</div>
          {byDate[d].map((it, i) => <Item key={i} item={it} />)}
        </div>
      ))}

      {data.status === "error" && <div className={errorCss}>⚠ Last update failed: {data.error}</div>}
      {data.generated_at && (
        <div className={footer}>
          Updated {data.generated_at.replace("T", " ")}{data.ranker && ` · Ranked by ${data.ranker}`}
        </div>
      )}
    </div>
  );
};
