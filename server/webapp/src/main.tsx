import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  BookOpen,
  Brain,
  Check,
  ChevronRight,
  CirclePlus,
  Clock3,
  Cloud,
  FileText,
  Layers3,
  Loader2,
  LogOut,
  RefreshCw,
  Save,
  Sparkles,
  Upload,
} from "lucide-react";
import "./styles.css";

const apiBase = "/api/v1";

type User = { id: string; email: string; display_name: string };
type Deck = {
  id: string;
  name: string;
  description: string;
  icon?: string;
  color?: string;
  new_cards_per_day?: number;
  max_reviews_per_day?: number;
};
type Card = {
  id: string;
  title: string;
  content: string;
  front: string;
  back: string;
  tags: string[];
  study_enabled: boolean;
};
type Draft = {
  title: string;
  content: string;
  front?: string;
  back?: string;
  tags?: string[];
  note?: string;
  quality_report?: { score: number; violations?: { message: string }[] };
};
type Job = {
  id: string;
  source_name?: string;
  status: "running" | "succeeded" | "failed";
  progress: number;
  error_message?: string;
  result?: { items?: Draft[]; document?: { title: string; text_length: number } };
};

function App() {
  const [token, setToken] = useState(() => localStorage.getItem("ank_token") || "");
  const [user, setUser] = useState<User | null>(() => {
    const raw = localStorage.getItem("ank_user");
    return raw ? JSON.parse(raw) : null;
  });
  const [decks, setDecks] = useState<Deck[]>([]);
  const [cards, setCards] = useState<Card[]>([]);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [selectedDrafts, setSelectedDrafts] = useState<Set<number>>(new Set());
  const [selectedDeckId, setSelectedDeckId] = useState(
    () => localStorage.getItem("ank_deck_id") || "",
  );
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState("");
  const [authMode, setAuthMode] = useState<"login" | "register">("login");
  const [authForm, setAuthForm] = useState({
    email: "",
    password: "",
    displayName: "Web User",
  });
  const [deckForm, setDeckForm] = useState({ name: "", description: "" });
  const [cardForm, setCardForm] = useState({
    title: "",
    front: "",
    back: "",
    tags: "",
    studyEnabled: true,
  });
  const [aiForm, setAiForm] = useState({
    topic: "",
    context: "",
    count: "",
  });
  const [file, setFile] = useState<File | null>(null);

  const selectedDeck = decks.find((deck) => deck.id === selectedDeckId);
  const selectedDraftCount = selectedDrafts.size;

  useEffect(() => {
    if (toast) {
      const id = window.setTimeout(() => setToast(""), 3200);
      return () => window.clearTimeout(id);
    }
    return undefined;
  }, [toast]);

  useEffect(() => {
    if (!token) return;
    void reloadAll();
  }, [token]);

  useEffect(() => {
    if (!token) return;
    const id = window.setInterval(() => {
      if (jobs.some((job) => job.status === "running")) {
        void loadJobs();
      }
    }, 3000);
    return () => window.clearInterval(id);
  }, [token, jobs]);

  const deckCards = useMemo(() => cards, [cards]);

  async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      ...(init.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
      ...(init.headers as Record<string, string> | undefined),
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${apiBase}${path}`, { ...init, headers });
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      throw new Error(body?.error || `${response.status} ${response.statusText}`);
    }
    if (response.status === 204) return null as T;
    return response.json();
  }

  async function reloadAll() {
    await loadDecks();
    await loadJobs();
  }

  async function loadDecks(preferredDeckId = selectedDeckId) {
    const body = await api<{ items: Deck[] }>("/decks");
    const nextDecks = body.items || [];
    setDecks(nextDecks);
    const nextSelected = nextDecks.some((deck) => deck.id === preferredDeckId)
      ? preferredDeckId
      : nextDecks[0]?.id || "";
    setSelectedDeckId(nextSelected);
    localStorage.setItem("ank_deck_id", nextSelected);
    if (nextSelected) await loadCards(nextSelected);
  }

  async function loadCards(deckId = selectedDeckId) {
    if (!deckId) {
      setCards([]);
      return;
    }
    const body = await api<{ items: Card[] }>(`/decks/${deckId}/cards`);
    setCards(body.items || []);
  }

  async function loadJobs() {
    const body = await api<{ items: Job[] }>("/ai/generate-jobs");
    setJobs(body.items || []);
  }

  async function authenticate(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const body = await api<{ user: User; access_token: string }>(`/auth/${authMode}`, {
        method: "POST",
        body: JSON.stringify({
          email: authForm.email.trim(),
          password: authForm.password,
          display_name: authForm.displayName.trim() || "Web User",
        }),
      });
      setToken(body.access_token);
      setUser(body.user);
      localStorage.setItem("ank_token", body.access_token);
      localStorage.setItem("ank_user", JSON.stringify(body.user));
      setToast(authMode === "register" ? "注册成功" : "登录成功");
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  function logout() {
    localStorage.removeItem("ank_token");
    localStorage.removeItem("ank_user");
    localStorage.removeItem("ank_deck_id");
    setToken("");
    setUser(null);
    setDecks([]);
    setCards([]);
    setJobs([]);
    setDrafts([]);
    setSelectedDeckId("");
  }

  async function createDeck(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const deck = await api<Deck>("/decks", {
        method: "POST",
        body: JSON.stringify({
          name: deckForm.name.trim(),
          description: deckForm.description.trim(),
          color: "#4ECDC4",
          icon: "book",
          review_order: "sequential",
          new_cards_per_day: 20,
          max_reviews_per_day: 200,
        }),
      });
      setDeckForm({ name: "", description: "" });
      setSelectedDeckId(deck.id);
      localStorage.setItem("ank_deck_id", deck.id);
      await loadDecks(deck.id);
      setToast("牌组已创建");
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  async function createCard(event: React.FormEvent) {
    event.preventDefault();
    if (!selectedDeckId) return setToast("请先选择牌组");
    setBusy(true);
    try {
      await api<Card>(`/decks/${selectedDeckId}/cards`, {
        method: "POST",
        body: JSON.stringify({
          title: cardForm.title.trim(),
          content: composeContent(cardForm.front, cardForm.back),
          front: cardForm.front.trim(),
          back: cardForm.back.trim(),
          tags: parseTags(cardForm.tags),
          note: "",
          source: "web",
          study_enabled: cardForm.studyEnabled,
        }),
      });
      setCardForm({ title: "", front: "", back: "", tags: "", studyEnabled: true });
      await loadCards();
      setToast("卡片已保存");
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  async function generateDrafts(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const body = await api<{ items: Draft[] }>("/ai/generate", {
        method: "POST",
        body: JSON.stringify(aiPayload()),
      });
      setDrafts(body.items || []);
      setSelectedDrafts(new Set((body.items || []).map((_, index) => index)));
      setToast(`已生成 ${(body.items || []).length} 张草稿`);
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  async function startBackgroundJob() {
    setBusy(true);
    try {
      if (file) {
        const form = new FormData();
        form.append("file", file);
        form.append("topic", aiForm.topic.trim() || selectedDeck?.name || "AI 制卡");
        if (aiForm.count.trim()) form.append("card_count", aiForm.count.trim());
        form.append("difficulty", "medium");
        form.append("card_types", "basic,single_choice,multi_choice,cloze");
        form.append("policy_json", JSON.stringify(policyPayload()));
        await api<Job>("/ai/import-file-job", { method: "POST", body: form });
      } else {
        await api<Job>("/ai/generate-jobs", {
          method: "POST",
          body: JSON.stringify(aiPayload()),
        });
      }
      await loadJobs();
      setToast("已转入后台生成");
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  async function saveSelectedDrafts() {
    if (!selectedDeckId) return setToast("请先选择牌组");
    const indexes = [...selectedDrafts].sort((a, b) => a - b);
    if (indexes.length === 0) return setToast("请选择要保存的草稿");
    setBusy(true);
    try {
      for (const index of indexes) {
        const draft = drafts[index];
        await api<Card>(`/decks/${selectedDeckId}/cards`, {
          method: "POST",
          body: JSON.stringify({
            title: draft.title || `AI 草稿 ${index + 1}`,
            content: draft.content || composeContent(draft.front || "", draft.back || ""),
            front: draft.front || promptOf(draft.content),
            back: draft.back || answerOf(draft.content),
            tags: draft.tags || ["AI生成"],
            note: draft.note || "",
            source: "web",
            study_enabled: true,
          }),
        });
      }
      setDrafts((current) => current.filter((_, index) => !indexes.includes(index)));
      setSelectedDrafts(new Set());
      await loadCards();
      setToast(`已保存 ${indexes.length} 张草稿`);
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  function aiPayload() {
    return {
      topic: aiForm.topic.trim() || selectedDeck?.name || "AI 制卡",
      context: aiForm.context.trim(),
      ...(Number(aiForm.count || 0) > 0 ? { card_count: Number(aiForm.count) } : {}),
      difficulty: "medium",
      policy: policyPayload(),
    };
  }

  function policyPayload() {
    return {
      name: "Web 精读规则",
      atomicity_level: "strict",
      answer_style: "one_sentence",
      max_answer_chars: 90,
      preferred_card_types: ["basic", "cloze", "single_choice", "multi_choice"],
      split_strategy: "by_heading",
      coverage_mode: "balanced",
      max_cards_total: 16,
      max_cards_per_chunk: 5,
      custom_rules: "题干聚焦单一知识点；选择题必须使用 Ank DSL；答案短、可自评。",
    };
  }

  if (!token) {
    return (
      <main className="auth-shell">
        <section className="auth-card">
          <div className="brand-mark"><Brain size={30} /></div>
          <p className="eyebrow">Ank Web Console</p>
          <h1>桌面制卡工作台</h1>
          <p className="subtle">登录后继续管理云端牌组、AI 草稿和背诵卡片。</p>
          <form onSubmit={authenticate} className="auth-form">
            <div className="segmented" role="tablist">
              <button type="button" className={authMode === "login" ? "active" : ""} onClick={() => setAuthMode("login")}>登录</button>
              <button type="button" className={authMode === "register" ? "active" : ""} onClick={() => setAuthMode("register")}>注册</button>
            </div>
            <label>邮箱<input type="email" value={authForm.email} onChange={(e) => setAuthForm({ ...authForm, email: e.target.value })} required /></label>
            <label>密码<input type="password" value={authForm.password} onChange={(e) => setAuthForm({ ...authForm, password: e.target.value })} required /></label>
            {authMode === "register" && (
              <label>昵称<input value={authForm.displayName} onChange={(e) => setAuthForm({ ...authForm, displayName: e.target.value })} /></label>
            )}
            <button className="primary" disabled={busy}>{busy ? <Loader2 className="spin" size={18} /> : <ChevronRight size={18} />}进入工作台</button>
          </form>
        </section>
        {toast && <div className="toast">{toast}</div>}
      </main>
    );
  }

  return (
    <main className="app-shell">
      <aside className="rail">
        <div className="rail-head">
          <div className="brand-mark"><Brain size={24} /></div>
          <div><strong>Ank</strong><span>Web Studio</span></div>
        </div>
        <button className="rail-action" onClick={() => void reloadAll()} disabled={busy}><RefreshCw size={17} />刷新</button>
        <form onSubmit={createDeck} className="deck-create">
          <input placeholder="新牌组名称" value={deckForm.name} onChange={(e) => setDeckForm({ ...deckForm, name: e.target.value })} required />
          <textarea placeholder="说明，可选" rows={2} value={deckForm.description} onChange={(e) => setDeckForm({ ...deckForm, description: e.target.value })} />
          <button disabled={busy}><CirclePlus size={17} />新建牌组</button>
        </form>
        <nav className="deck-list">
          {decks.map((deck) => (
            <button key={deck.id} className={deck.id === selectedDeckId ? "deck active" : "deck"} onClick={() => { setSelectedDeckId(deck.id); localStorage.setItem("ank_deck_id", deck.id); void loadCards(deck.id); }}>
              <BookOpen size={18} />
              <span><strong>{deck.name}</strong><small>{deck.description || "无说明"}</small></span>
            </button>
          ))}
        </nav>
        <div className="user-strip">
          <span>{user?.display_name || user?.email}</span>
          <button onClick={logout} title="退出"><LogOut size={17} /></button>
        </div>
      </aside>

      <section className="studio">
        <header className="topbar">
          <div>
            <p className="eyebrow">AI Drafting</p>
            <h1>{selectedDeck?.name || "选择一个牌组"}</h1>
          </div>
          <div className="metrics">
            <span><Layers3 size={16} />{decks.length} 牌组</span>
            <span><FileText size={16} />{deckCards.length} 卡片</span>
            <span><Clock3 size={16} />{jobs.filter((job) => job.status === "running").length} 生成中</span>
          </div>
        </header>

        <section className="ai-panel">
          <div className="panel-title">
            <Sparkles size={20} />
            <div><h2>AI 制卡</h2><p>可以同步生成，也可以放到后台后再取回。</p></div>
          </div>
          <form onSubmit={generateDrafts} className="ai-grid">
            <label>主题<input value={aiForm.topic} onChange={(e) => setAiForm({ ...aiForm, topic: e.target.value })} placeholder="教育学原理：形成性评价" /></label>
            <label>数量（可选）<input type="number" min={1} max={20} value={aiForm.count} onChange={(e) => setAiForm({ ...aiForm, count: e.target.value })} placeholder="留空自动拆分" /></label>
            <label className="wide">材料 / 要求<textarea rows={5} value={aiForm.context} onChange={(e) => setAiForm({ ...aiForm, context: e.target.value })} placeholder="粘贴知识点、教材片段，或描述你想要的卡片。" /></label>
            <label className="file-drop"><Upload size={18} />{file ? file.name : "可选：后台生成可读取 PDF / Markdown / TXT"}<input type="file" accept=".pdf,.md,.markdown,.txt" onChange={(e) => setFile(e.target.files?.[0] || null)} /></label>
            <div className="wide actions-row">
              <button className="primary" disabled={busy}>{busy ? <Loader2 className="spin" size={18} /> : <Sparkles size={18} />}生成草稿</button>
              <button type="button" className="secondary" onClick={() => void startBackgroundJob()} disabled={busy}><Cloud size={18} />后台生成</button>
            </div>
          </form>
        </section>

        <section className="job-strip">
          {jobs.slice(0, 4).map((job) => (
            <article key={job.id} className={`job ${job.status}`}>
              <div><strong>{job.source_name || "后台生成任务"}</strong><span>{job.status === "succeeded" ? `${job.result?.items?.length || 0} 张草稿可取回` : job.status === "failed" ? job.error_message || "生成失败" : `生成中 ${Math.round((job.progress || 0) * 100)}%`}</span></div>
              <button disabled={!job.result?.items?.length} onClick={() => { const items = job.result?.items || []; setDrafts(items); setSelectedDrafts(new Set(items.map((_, i) => i))); setToast(`已取回 ${items.length} 张草稿`); }}>取回</button>
            </article>
          ))}
        </section>

        <section className="draft-board">
          <div className="board-head">
            <div><h2>草稿预览</h2><p>{drafts.length ? `已选择 ${selectedDraftCount} / ${drafts.length} 张` : "生成后的卡片会在这里逐张确认。"}</p></div>
            <div className="board-actions">
              <button disabled={!drafts.length || busy} onClick={() => setSelectedDrafts(new Set(drafts.map((_, i) => i)))}><Check size={16} />全选</button>
              <button disabled={!drafts.length || busy} onClick={() => setSelectedDrafts(new Set())}>取消</button>
              <button className="primary" disabled={!drafts.length || !selectedDrafts.size || busy} onClick={() => void saveSelectedDrafts()}><Save size={16} />保存所选</button>
            </div>
          </div>
          <div className="draft-grid">
            {drafts.length === 0 ? (
              <div className="empty-state"><Sparkles size={28} /><strong>等待第一批 AI 草稿</strong><span>同步生成适合短材料；教材或 PDF 建议后台生成。</span></div>
            ) : drafts.map((draft, index) => (
              <article key={`${draft.title}-${index}`} className={selectedDrafts.has(index) ? "draft selected" : "draft"}>
                <label className="draft-check"><input type="checkbox" checked={selectedDrafts.has(index)} onChange={(e) => toggleDraft(index, e.target.checked, selectedDrafts, setSelectedDrafts)} />保存</label>
                <h3>{draft.title || `草稿 ${index + 1}`}</h3>
                <pre>{promptOf(draft.content || draft.front || "")}</pre>
                <p>{draft.back || answerOf(draft.content || "")}</p>
                <div className="tags">{(draft.tags || ["AI生成"]).slice(0, 4).map((tag) => <span key={tag}>{tag}</span>)}</div>
              </article>
            ))}
          </div>
        </section>
      </section>

      <aside className="inspector">
        <section className="manual-card">
          <h2>手工建卡</h2>
          <form onSubmit={createCard}>
            <label>标题<input value={cardForm.title} onChange={(e) => setCardForm({ ...cardForm, title: e.target.value })} placeholder="题目" required /></label>
            <label>正面 / DSL<textarea rows={5} value={cardForm.front} onChange={(e) => setCardForm({ ...cardForm, front: e.target.value })} required /></label>
            <label>答案<textarea rows={4} value={cardForm.back} onChange={(e) => setCardForm({ ...cardForm, back: e.target.value })} required /></label>
            <label>标签<input value={cardForm.tags} onChange={(e) => setCardForm({ ...cardForm, tags: e.target.value })} placeholder="教育学, 考试" /></label>
            <label className="inline"><input type="checkbox" checked={cardForm.studyEnabled} onChange={(e) => setCardForm({ ...cardForm, studyEnabled: e.target.checked })} />加入背诵</label>
            <button className="primary" disabled={busy}><Save size={17} />保存卡片</button>
          </form>
        </section>
        <section className="card-list">
          <h2>当前卡片</h2>
          {deckCards.slice(0, 12).map((card) => (
            <article key={card.id} className="saved-card">
              <strong>{card.title || card.front || "未命名卡片"}</strong>
              <p>{card.back || answerOf(card.content)}</p>
              <span>{card.study_enabled ? "已加入背诵" : "未加入背诵"}</span>
            </article>
          ))}
        </section>
      </aside>
      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}

function toggleDraft(index: number, checked: boolean, current: Set<number>, setter: (next: Set<number>) => void) {
  const next = new Set(current);
  if (checked) next.add(index);
  else next.delete(index);
  setter(next);
}

function parseTags(value: string) {
  return value.split(/[,，;；\s]+/).map((tag) => tag.trim()).filter(Boolean);
}

function composeContent(front: string, back: string) {
  const prompt = front.trim();
  const answer = back.trim();
  return answer ? `${prompt}\n\n@answer\n${answer}\n@end` : prompt;
}

function promptOf(content = "") {
  return content.split("@answer")[0].trim();
}

function answerOf(content = "") {
  const match = content.match(/@answer\s*([\s\S]*?)\s*@end/);
  return match?.[1]?.trim() || "";
}

createRoot(document.getElementById("root")!).render(<App />);
