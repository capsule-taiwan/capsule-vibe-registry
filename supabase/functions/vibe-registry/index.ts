// vibe-registry 唯一寫入閘道
// 客戶端只持有 REGISTRY_TOKEN（只對本函式有效）；資料庫憑證 (service_role)
// 與 Slack webhook 只存在伺服器端 secrets，不落地到任何使用者機器。
// 部署：npx supabase functions deploy vibe-registry --project-ref <ref> --no-verify-jwt
// Secrets：npx supabase secrets set REGISTRY_TOKEN=... SLACK_WEBHOOK_URL=... --project-ref <ref>
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const TOKEN = Deno.env.get("REGISTRY_TOKEN") ?? "";
const SLACK = Deno.env.get("SLACK_WEBHOOK_URL") ?? "";

const COLS = "id,title,owner,members,status,description,latest_update,updated_at";
const STATUSES = ["active", "paused", "done"];

async function slack(text: string) {
  if (!SLACK) return;
  try {
    await fetch(SLACK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
  } catch (_) { /* 通知失敗不影響主流程 */ }
}

function csvCell(v: unknown): string {
  const s = v == null ? "" : Array.isArray(v) ? `{${v.join(",")}}` : String(v);
  return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}

const text = (s: string, status = 200) =>
  new Response(s, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });

Deno.serve(async (req) => {
  if (!TOKEN || req.headers.get("x-registry-token") !== TOKEN) {
    return text("unauthorized", 401);
  }
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return text("bad request: body 必須是 JSON", 400);
  }
  const action = body.action as string;
  const t = () => supabase.from("vibe_projects");

  if (action === "list") {
    let q = t().select(COLS).order("updated_at", { ascending: false }).limit(200);
    if (!body.all) q = q.in("status", ["active", "paused", "stale"]);
    const { data, error } = await q;
    if (error) return text(error.message, 500);
    const rows = data.map((r) =>
      [r.id, r.title, r.owner, r.members, r.status, r.description, r.latest_update, r.updated_at]
        .map(csvCell).join(",")
    );
    return text([COLS, ...rows].join("\n"));
  }

  if (action === "add") {
    const title = String(body.title ?? "").trim();
    const description = String(body.description ?? "").trim();
    const owner = String(body.owner ?? "").trim().toLowerCase();
    if (!title || !owner.includes("@")) return text("title 與 owner (email) 必填", 400);
    const { data, error } = await t().insert({ title, description, owner }).select("id").single();
    if (error) return text(error.message, 500);
    await slack(`🆕 ${owner} 開始新的 vibe coding 專案:${title} - ${description}`);
    return text(`已登記 (id: ${data.id})`);
  }

  if (action === "join") {
    const id = String(body.id ?? "");
    const me = String(body.me ?? "").trim().toLowerCase();
    if (!id || !me.includes("@")) return text("id 與 me (email) 必填", 400);
    const { data: row, error } = await t().select("title,owner,members").eq("id", id).maybeSingle();
    if (error) return text(error.message, 500);
    if (!row) return text(`找不到 id=${id} 的專案`, 404);
    if (row.owner === me) return text("你是這個專案的發起人,不需要加入");
    if ((row.members ?? []).includes(me)) return text("你已經是這個專案的成員");
    const members = [...(row.members ?? []), me];
    const { error: e2 } = await t().update({ members }).eq("id", id);
    if (e2) return text(e2.message, 500);
    await slack(`👥 ${me} 加入了專案:${row.title} (發起人 ${row.owner})`);
    return text(`已加入專案「${row.title}」(發起人:${row.owner})`);
  }

  if (action === "update") {
    const id = String(body.id ?? "");
    const note = String(body.note ?? "").trim();
    if (!id || !note) return text("id 與 note 必填", 400);
    const { data, error } = await t().update({ latest_update: note, status: "active" })
      .eq("id", id).select("id");
    if (error) return text(error.message, 500);
    if (!data.length) return text(`找不到 id=${id} 的專案`, 404);
    return text(`已更新進度:${note}`);
  }

  if (action === "status") {
    const id = String(body.id ?? "");
    const status = String(body.status ?? "");
    const me = String(body.me ?? "").trim().toLowerCase();
    if (!id || !STATUSES.includes(status)) {
      return text(`status 只能是 ${STATUSES.join("|")}`, 400);
    }
    const { data, error } = await t().update({ status }).eq("id", id).select("title,owner");
    if (error) return text(error.message, 500);
    if (!data.length) return text(`找不到 id=${id} 的專案`, 404);
    if (status === "done") {
      await slack(`✅ ${me || data[0].owner} 完成了專案:${data[0].title}`);
    }
    return text(`已更新狀態為 ${status}:${data[0].title}`);
  }

  return text(`未知的 action:${action}`, 400);
});
