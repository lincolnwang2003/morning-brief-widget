import { css, run } from "uebersicht";

const PROJECT = "/Users/peilinwang/Desktop/pm-extra-credit";
const PY = "/opt/homebrew/bin/python3";

// The task list plus the ids I've checked off (data/done.json), in one JSON object.
export const command = `cd "${PROJECT}/data" && printf '{"brief":%s,"done":%s}' \
  "$(cat today.json 2>/dev/null || echo '{}')" "$(cat done.json 2>/dev/null || echo '{}')"`;
export const refreshFrequency = 10 * 1000;

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
`;
const check = css`
  width: 14px; height: 14px; border-radius: 50%; margin-top: 2px; flex-shrink: 0;
  border: 2px solid; box-sizing: border-box; cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  font-size: 9px; font-weight: 700; color: transparent;
  &:hover { color: #1c1c1e; }
`;
const titleCss = css`font-size: 13px; line-height: 1.35;`;
const meta = css`font-size: 11px; color: #98989d; margin-top: 1px;`;
const button = css`
  font-size: 11px; color: #0a84ff; cursor: pointer; background: none; border: none; padding: 0;
`;
const footer = css`
  font-size: 10px; color: #6e6e73; margin-top: 12px;
  display: flex; justify-content: space-between; gap: 8px;
`;
const errorCss = css`font-size: 11px; color: #ff9f0a; margin-top: 8px;`;

const COLORS = { high: "#ff453a", medium: "#ffd60a", low: "#8e8e93" };
const SOURCE_LABEL = { canvas: "Canvas", calendar: "Calendar", gmail: "Email" };

// Widget state: the latest command output, plus ids hidden right away when checked (before the next refresh).
export const initialState = { output: "", hidden: [] };
export const updateState = (event, prev) => {
  switch (event.type) {
    case "UB/COMMAND_RAN": return { ...prev, output: event.output };
    case "HIDE": return { ...prev, hidden: [...prev.hidden, event.id] };
    case "UNDO": return { ...prev, hidden: [] };
    default: return prev;
  }
};

const refresh = () => run(`cd "${PROJECT}" && nohup ${PY} run.py >/dev/null 2>&1 &`);

const markDone = (item, dispatch) => {
  dispatch({ type: "HIDE", id: item.id });
  const title = (item.title || "").replace(/[^\w .:-]/g, " ");
  run(`${PY} "${PROJECT}/tasks.py" done ${item.id} "${title}"`);
};

const undo = (dispatch) => run(`${PY} "${PROJECT}/tasks.py" undo`).then(() => dispatch({ type: "UNDO" }));

const Item = ({ item, dispatch }) => {
  const clickable = item.link && item.link.startsWith("http");
  const color = COLORS[item.priority] || COLORS.low;
  const confidence = item.confidence != null && `${Math.round(item.confidence * 100)}%`;
  return (
    <div className={row}>
      <div
        className={check}
        style={{ borderColor: color, background: `${color}33` }}
        title="Mark as done"
        onClick={() => item.id && markDone(item, dispatch)}
      >
        ✓
      </div>
      <div
        style={{ cursor: clickable ? "pointer" : "default" }}
        onClick={() => clickable && run(`open "${item.link.replace(/"/g, "")}"`)}
      >
        <div className={titleCss}>{item.title}</div>
        <div className={meta}>
          {[item.time, item.reason, confidence, (item.sources || []).map((s) => SOURCE_LABEL[s] || s).join(" · ")]
            .filter(Boolean)
            .join("  ·  ")}
        </div>
      </div>
    </div>
  );
};

const dayLabel = (iso) =>
  new Date(iso + "T12:00:00").toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });

export const render = ({ output, hidden }, dispatch) => {
  let data = {}, done = {};
  try { ({ brief: data, done } = JSON.parse(output)); } catch (e) {}

  const visible = (it) => !(it.id in done) && !hidden.includes(it.id);
  const all = [...(data.today || []), ...(data.upcoming || [])];
  const today = (data.today || []).filter(visible);
  const upcoming = (data.upcoming || []).filter(visible);
  const byDate = upcoming.reduce((acc, it) => ((acc[it.date] = acc[it.date] || []).push(it), acc), {});
  const doneCount = all.filter((it) => !visible(it)).length;

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
      {today.length ? today.map((it) => <Item key={it.id || it.title} item={it} dispatch={dispatch} />)
                    : <div className={meta}>{data.generated_at ? "Nothing left for today 🎉" : "Nothing yet — click Refresh."}</div>}

      {Object.keys(byDate).sort().map((d) => (
        <div key={d}>
          <div className={h2}>{dayLabel(d)}</div>
          {byDate[d].map((it) => <Item key={it.id || it.title} item={it} dispatch={dispatch} />)}
        </div>
      ))}

      {data.status === "error" && <div className={errorCss}>⚠ Last update failed: {data.error}</div>}
      {data.generated_at && (
        <div className={footer}>
          <span>Updated {data.generated_at.replace("T", " ")}{data.ranker && ` · Ranked by ${data.ranker}`}</span>
          {doneCount > 0 && (
            <span style={{ whiteSpace: "nowrap" }}>
              ✓ {doneCount} done · <button className={button} style={{ fontSize: 10 }} onClick={() => undo(dispatch)}>Undo</button>
            </span>
          )}
        </div>
      )}
    </div>
  );
};
