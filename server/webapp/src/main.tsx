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
import { answerOf, cardToPreview, draftToPreview, previewFront, promptOf } from "./cardPreview";
import { estimateGeneration } from "./generationEstimate";
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
type ManualCardType = "basic" | "single_choice" | "multi_choice" | "cloze";
type ManualOption = { text: string; correct: boolean };

const defaultManualOptions: ManualOption[] = [
  { text: "", correct: true },
  { text: "", correct: false },
  { text: "", correct: false },
  { text: "", correct: false },
];

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
  const [selectedCardId, setSelectedCardId] = useState("");
  const [previewDraftIndex, setPreviewDraftIndex] = useState<number | null>(null);
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
    type: "basic" as ManualCardType,
    title: "",
    question: "",
    answer: "",
    tags: "",
    studyEnabled: true,
    options: defaultManualOptions,
  });
  const [aiForm, setAiForm] = useState({
    topic: "",
    context: "",
    count: "",
    learningGoal: "理解并长期记忆",
    allowWebSearch: false,
    examMode: false,
    strictSource: true,
  });
  const [file, setFile] = useState<File | null>(null);

  const selectedDeck = decks.find((deck) => deck.id === selectedDeckId);
  const selectedDraftCount = selectedDrafts.size;
  const selectedCard = cards.find((card) => card.id === selectedCardId) || cards[0];
  const generationEstimate = estimateGeneration({
    contextLength: aiForm.context.length,
    fileSize: file?.size,
    cardCount: Number(aiForm.count || 0),
    hasFile: Boolean(file),
    allowWebSearch: aiForm.allowWebSearch,
    examMode: aiForm.examMode,
  });
  const manualPreview = {
    title: cardForm.title.trim() || "正在制作的新卡片",
    front: manualPreviewFront(cardForm),
    back: manualPreviewBack(cardForm),
    tags: parseTags(cardForm.tags),
    studyEnabled: cardForm.studyEnabled,
    source: "manual" as const,
  };
  const draftPreview = previewDraftIndex === null ? null : draftToPreview(drafts[previewDraftIndex]);
  const savedPreview = selectedCard ? cardToPreview(selectedCard) : null;
  const hasManualPreview = Boolean(cardForm.title.trim() || cardForm.question.trim() || cardForm.answer.trim() || cardForm.options.some((option) => option.text.trim()));
  const activePreview = hasManualPreview ? manualPreview : draftPreview || savedPreview;

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

  async function loadCards(deckId = selectedDeckId, preferredCardId = selectedCardId) {
    if (!deckId) {
      setCards([]);
      setSelectedCardId("");
      return;
    }
    const body = await api<{ items: Card[] }>(`/decks/${deckId}/cards`);
    const nextCards = body.items || [];
    setCards(nextCards);
    const nextSelected = nextCards.some((card) => card.id === preferredCardId)
      ? preferredCardId
      : nextCards[0]?.id || "";
    setSelectedCardId(nextSelected);
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
    const manual = composeManualCard(cardForm);
    if (!manual.ok) return setToast(manual.error);
    setBusy(true);
    try {
      const card = await api<Card>(`/decks/${selectedDeckId}/cards`, {
        method: "POST",
        body: JSON.stringify({
          title: cardForm.title.trim(),
          content: manual.content,
          front: manual.front,
          back: manual.back,
          tags: parseTags(cardForm.tags),
          note: "",
          source: "web",
          study_enabled: cardForm.studyEnabled,
        }),
      });
      setCardForm({
        type: "basic",
        title: "",
        question: "",
        answer: "",
        tags: "",
        studyEnabled: true,
        options: defaultManualOptions,
      });
      setPreviewDraftIndex(null);
      await loadCards(selectedDeckId, card.id);
      setToast("卡片已保存");
    } catch (error) {
      setToast(String(error instanceof Error ? error.message : error));
    } finally {
      setBusy(false);
    }
  }

  async function startGeneration(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      if (generationEstimate.shouldUseBackground) {
        await createGenerationJob();
        await loadJobs();
        setToast(`已转入后台任务，预计 ${generationEstimate.label}`);
        return;
      }
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

  async function createGenerationJob() {
    if (file) {
      const form = new FormData();
      form.append("file", file);
      form.append("topic", aiForm.topic.trim() || selectedDeck?.name || "AI 制卡");
      if (aiForm.count.trim()) form.append("card_count", aiForm.count.trim());
      form.append("difficulty", "medium");
      form.append("card_types", "basic,single_choice,multi_choice,cloze");
      form.append("learning_goal", aiForm.learningGoal.trim());
      form.append("allow_web_search", String(aiForm.allowWebSearch));
      form.append("exam_mode", String(aiForm.examMode));
      form.append("strict_source", String(aiForm.strictSource));
      form.append("policy_json", JSON.stringify(policyPayload()));
      await api<Job>("/ai/import-file-job", { method: "POST", body: form });
      return;
    }
    await api<Job>("/ai/generate-jobs", {
      method: "POST",
      body: JSON.stringify(aiPayload()),
    });
  }

  async function saveSelectedDrafts() {
    if (!selectedDeckId) return setToast("请先选择牌组");
    const indexes = [...selectedDrafts].sort((a, b) => a - b);
    if (indexes.length === 0) return setToast("请选择要保存的草稿");
    setBusy(true);
    try {
      let firstSavedCardId = "";
      for (const index of indexes) {
        const draft = drafts[index];
        const card = await api<Card>(`/decks/${selectedDeckId}/cards`, {
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
        if (!firstSavedCardId) firstSavedCardId = card.id;
      }
      setDrafts((current) => current.filter((_, index) => !indexes.includes(index)));
      setSelectedDrafts(new Set());
      setPreviewDraftIndex(null);
      await loadCards(selectedDeckId, firstSavedCardId);
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
      learning_goal: aiForm.learningGoal.trim(),
      allow_web_search: aiForm.allowWebSearch,
      exam_mode: aiForm.examMode,
      strict_source: aiForm.strictSource,
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
      custom_rules: "不预设卡片数量，由模型根据材料密度自主拆分；模型自主选择题型；题干聚焦单一知识点；选择题必须使用 Ank DSL；答案短、可自评。",
    };
  }

  function updateCardForm(patch: Partial<typeof cardForm>) {
    setCardForm((current) => ({ ...current, ...patch }));
    setPreviewDraftIndex(null);
  }

  function updateManualOption(index: number, patch: Partial<ManualOption>) {
    setCardForm((current) => {
      const options = current.options.map((option, optionIndex) => {
        if (optionIndex !== index) {
          return current.type === "single_choice" && patch.correct ? { ...option, correct: false } : option;
        }
        return { ...option, ...patch };
      });
      return { ...current, options };
    });
    setPreviewDraftIndex(null);
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
        <section className="rail-section">
          <div className="section-title"><h2>牌组</h2><span>{decks.length}</span></div>
          <form onSubmit={createDeck} className="deck-create">
            <input placeholder="新牌组名称" value={deckForm.name} onChange={(e) => setDeckForm({ ...deckForm, name: e.target.value })} required />
            <textarea placeholder="说明，可选" rows={2} value={deckForm.description} onChange={(e) => setDeckForm({ ...deckForm, description: e.target.value })} />
            <button disabled={busy}><CirclePlus size={17} />新建牌组</button>
          </form>
          <nav className="deck-list">
            {decks.map((deck) => (
              <button key={deck.id} className={deck.id === selectedDeckId ? "deck active" : "deck"} onClick={() => { setSelectedDeckId(deck.id); localStorage.setItem("ank_deck_id", deck.id); setPreviewDraftIndex(null); void loadCards(deck.id); }}>
                <BookOpen size={18} />
                <span><strong>{deck.name}</strong><small>{deck.description || "无说明"}</small></span>
              </button>
            ))}
          </nav>
        </section>
        <section className="card-browser">
          <div className="section-title"><h2>卡片列表</h2><span>{deckCards.length}</span></div>
          <div className="card-list-nav">
            {deckCards.length === 0 ? (
              <div className="mini-empty">当前牌组还没有卡片，先在中间制作一张。</div>
            ) : deckCards.map((card, index) => (
              <button key={card.id} className={card.id === selectedCardId && previewDraftIndex === null ? "card-row active" : "card-row"} onClick={() => { setSelectedCardId(card.id); setPreviewDraftIndex(null); }}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                <strong>{card.title || card.front || "未命名卡片"}</strong>
                <small>{card.back || answerOf(card.content) || "暂无答案"}</small>
              </button>
            ))}
          </div>
        </section>
        <div className="user-strip">
          <span>{user?.display_name || user?.email}</span>
          <button onClick={logout} title="退出"><LogOut size={17} /></button>
        </div>
      </aside>

      <section className="studio">
        <header className="topbar">
          <div>
            <p className="eyebrow">Card Workshop</p>
            <h1>制作卡片</h1>
            <p className="subtle">当前牌组：{selectedDeck?.name || "请选择牌组"}</p>
          </div>
          <div className="metrics">
            <span><Layers3 size={16} />{decks.length} 牌组</span>
            <span><FileText size={16} />{deckCards.length} 卡片</span>
            <span><Clock3 size={16} />{jobs.filter((job) => job.status === "running").length} 生成中</span>
          </div>
        </header>

	        <section className="maker-panel ai-panel">
	          <div className="panel-title">
	            <Sparkles size={20} />
	            <div><h2>AI 来做</h2><p>给模型目标和材料，Agent 会自主选择题型；联网只在你允许时启用。</p></div>
	          </div>
	          <form onSubmit={startGeneration} className="ai-grid">
	            <label>主题<input value={aiForm.topic} onChange={(e) => setAiForm({ ...aiForm, topic: e.target.value })} placeholder="教育学原理：形成性评价" /></label>
	            <label>数量（可选）<input type="number" min={1} value={aiForm.count} onChange={(e) => setAiForm({ ...aiForm, count: e.target.value })} placeholder="留空由 AI 拆分" /></label>
	            <label className="wide">学习目标<input value={aiForm.learningGoal} onChange={(e) => setAiForm({ ...aiForm, learningGoal: e.target.value })} placeholder="例如：408 考试强化、长期记忆、面试速记" /></label>
	            <div className="wide agent-options">
	              <label className="switch-card">
	                <input type="checkbox" checked={aiForm.examMode} onChange={(e) => setAiForm({ ...aiForm, examMode: e.target.checked })} />
	                <span><strong>考试强化</strong><small>让模型主动考虑易错点、混淆点和场景迁移。</small></span>
	              </label>
	              <label className="switch-card">
	                <input type="checkbox" checked={aiForm.allowWebSearch} onChange={(e) => setAiForm({ ...aiForm, allowWebSearch: e.target.checked, strictSource: e.target.checked ? aiForm.strictSource : true })} />
	                <span><strong>允许联网</strong><small>为考试背景、常见误区等提供搜索工具。</small></span>
	              </label>
	              <label className="switch-card">
	                <input type="checkbox" checked={aiForm.strictSource} disabled={!aiForm.allowWebSearch} onChange={(e) => setAiForm({ ...aiForm, strictSource: e.target.checked })} />
	                <span><strong>严格原文</strong><small>开启时只基于你的材料；关闭需同时允许联网。</small></span>
	              </label>
	            </div>
	            <label className="wide">材料 / 要求<textarea rows={5} value={aiForm.context} onChange={(e) => setAiForm({ ...aiForm, context: e.target.value })} placeholder="粘贴知识点、教材片段，或描述你想要的卡片。" /></label>
	            <label className="file-drop"><Upload size={18} />{file ? file.name : "可选：上传 PDF / Markdown / TXT"}<input type="file" accept=".pdf,.md,.markdown,.txt" onChange={(e) => setFile(e.target.files?.[0] || null)} /></label>
	            <div className="wide generation-summary">
	              <span><Clock3 size={16} />预计 {generationEstimate.label}</span>
	              <strong>{generationEstimate.modeLabel}</strong>
	            </div>
	            <div className="wide actions-row">
	              <button className="primary" disabled={busy}>{busy ? <Loader2 className="spin" size={18} /> : generationEstimate.shouldUseBackground ? <Cloud size={18} /> : <Sparkles size={18} />}开始生成</button>
	            </div>
	          </form>
	        </section>

        <section className="maker-panel manual-card">
          <div className="panel-title">
            <Save size={20} />
            <div><h2>手工制作</h2><p>适合快速补充、修正 AI 草稿，右侧会实时预览整张卡片。</p></div>
          </div>
          <form onSubmit={createCard} className="manual-grid">
            <label>标题<input value={cardForm.title} onChange={(e) => updateCardForm({ title: e.target.value })} placeholder="题目" required /></label>
            <div className="visual-card-type">
              {[
                ["basic", "问答卡"],
                ["single_choice", "单选题"],
                ["multi_choice", "多选题"],
                ["cloze", "填空卡"],
              ].map(([type, label]) => (
                <button key={type} type="button" className={cardForm.type === type ? "active" : ""} onClick={() => updateCardForm({ type: type as ManualCardType })}>{label}</button>
              ))}
            </div>
            <label className="wide">{cardForm.type === "cloze" ? "填空文本" : "题干"}<textarea rows={4} value={cardForm.question} onChange={(e) => updateCardForm({ question: e.target.value })} required placeholder={cardForm.type === "cloze" ? "例如：Cache 利用 {{局部性原理}} 提高访存速度" : "输入你希望用户回忆或判断的问题"} /></label>
            {(cardForm.type === "single_choice" || cardForm.type === "multi_choice") && (
              <div className="wide option-editor">
                <div className="option-editor-head"><strong>选项</strong><span>{cardForm.type === "single_choice" ? "选择一个正确答案" : "可选择多个正确答案"}</span></div>
                {cardForm.options.map((option, index) => (
                  <div key={index} className="option-row">
                    <label className="option-correct"><input type={cardForm.type === "single_choice" ? "radio" : "checkbox"} name="manual-correct-option" checked={option.correct} onChange={(e) => updateManualOption(index, { correct: e.target.checked })} />正确</label>
                    <input value={option.text} onChange={(e) => updateManualOption(index, { text: e.target.value })} placeholder={`选项 ${index + 1}`} />
                  </div>
                ))}
                <button type="button" onClick={() => updateCardForm({ options: [...cardForm.options, { text: "", correct: false }] })}>添加选项</button>
              </div>
            )}
            <label className="wide">{cardForm.type === "basic" ? "答案" : "答案解析"}<textarea rows={4} value={cardForm.answer} onChange={(e) => updateCardForm({ answer: e.target.value })} placeholder="用于自评的标准答案或解析" /></label>
            <label>标签<input value={cardForm.tags} onChange={(e) => { setCardForm({ ...cardForm, tags: e.target.value }); setPreviewDraftIndex(null); }} placeholder="教育学, 考试" /></label>
            <label className="inline"><input type="checkbox" checked={cardForm.studyEnabled} onChange={(e) => setCardForm({ ...cardForm, studyEnabled: e.target.checked })} />加入背诵</label>
            <div className="wide actions-row">
              <button className="primary" disabled={busy}><Save size={17} />保存卡片</button>
            </div>
          </form>
        </section>

        <section className="job-strip">
          {jobs.slice(0, 4).map((job) => (
            <article key={job.id} className={`job ${job.status}`}>
              <div><strong>{job.source_name || "后台任务"}</strong><span>{job.status === "succeeded" ? `${job.result?.items?.length || 0} 张草稿可取回` : job.status === "failed" ? job.error_message || "生成失败" : `处理中 ${Math.round((job.progress || 0) * 100)}%`}</span></div>
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
              <div className="empty-state"><Sparkles size={28} /><strong>等待第一批 AI 草稿</strong><span>短材料会直接显示草稿；文件、联网增强或长材料会自动进入后台任务。</span></div>
            ) : drafts.map((draft, index) => (
              <article key={`${draft.title}-${index}`} className={previewDraftIndex === index ? "draft previewing" : selectedDrafts.has(index) ? "draft selected" : "draft"} onClick={() => { setPreviewDraftIndex(index); setSelectedCardId(""); }}>
                <label className="draft-check" onClick={(event) => event.stopPropagation()}><input type="checkbox" checked={selectedDrafts.has(index)} onChange={(e) => toggleDraft(index, e.target.checked, selectedDrafts, setSelectedDrafts)} />保存</label>
                <h3>{draft.title || `草稿 ${index + 1}`}</h3>
                <pre>{previewFront(draft.content, draft.front)}</pre>
                <p>{draft.back || answerOf(draft.content || "")}</p>
                <div className="tags">{(draft.tags || ["AI生成"]).slice(0, 4).map((tag) => <span key={tag}>{tag}</span>)}</div>
              </article>
            ))}
          </div>
        </section>
      </section>

      <aside className="preview-pane">
        <section className="preview-card-shell">
          <p className="eyebrow">Card Preview</p>
          <h2>整张卡片预览</h2>
          {activePreview ? (
            <article className={`full-card ${activePreview.source}`}>
              <div className="preview-kicker">{activePreview.source === "draft" ? "AI 草稿" : activePreview.source === "manual" ? "正在制作" : "已保存卡片"}</div>
              <h3>{activePreview.title}</h3>
              <div className="preview-block">
                <span>正面</span>
                <pre>{activePreview.front || "还没有填写正面内容"}</pre>
              </div>
              <div className="preview-block answer">
                <span>答案</span>
                <p>{activePreview.back || "还没有填写答案"}</p>
              </div>
              <div className="preview-footer">
                <div className="tags">{activePreview.tags.length ? activePreview.tags.map((tag) => <span key={tag}>{tag}</span>) : <span>未设置标签</span>}</div>
                <strong>{activePreview.studyEnabled ? "将加入背诵" : "仅保存，不背诵"}</strong>
              </div>
            </article>
          ) : (
            <div className="preview-empty">
              <Sparkles size={30} />
              <strong>选择或制作一张卡片</strong>
              <span>左侧点卡片，中间点 AI 草稿，或开始手工输入。</span>
            </div>
          )}
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

function composeManualCard(form: {
  type: ManualCardType;
  title: string;
  question: string;
  answer: string;
  options: ManualOption[];
}): { ok: true; content: string; front: string; back: string } | { ok: false; error: string } {
  const question = form.question.trim();
  const answer = form.answer.trim();
  if (!question) return { ok: false, error: "请填写题干" };
  if (form.type === "basic" && !answer) return { ok: false, error: "请填写答案" };

  if (form.type === "single_choice" || form.type === "multi_choice") {
    const options = form.options
      .map((option) => ({ text: option.text.trim(), correct: option.correct }))
      .filter((option) => option.text);
    if (options.length < 2) return { ok: false, error: "选择题至少需要两个选项" };
    const correct = options.filter((option) => option.correct);
    if (form.type === "single_choice" && correct.length !== 1) {
      return { ok: false, error: "单选题必须且只能设置一个正确答案" };
    }
    if (form.type === "multi_choice" && correct.length < 1) {
      return { ok: false, error: "多选题至少需要一个正确答案" };
    }
    const blockName = form.type === "single_choice" ? "single-choice" : "multi-choice";
    const front = [
      `{${blockName}}`,
      `Q: ${question}`,
      ...options.map((option) => `${option.correct ? "*" : "-"} ${option.text}`),
      `{/${blockName}}`,
    ].join("\n");
    const back = answer || correct.map((option) => option.text).join("；");
    return { ok: true, front, back, content: composeContent(front, back) };
  }

  return { ok: true, front: question, back: answer, content: composeContent(question, answer) };
}

function manualPreviewFront(form: {
  type: ManualCardType;
  question: string;
  options: ManualOption[];
}) {
  const question = form.question.trim();
  if (form.type !== "single_choice" && form.type !== "multi_choice") {
    return question;
  }
  const options = form.options
    .map((option, index) => ({ ...option, text: option.text.trim(), index }))
    .filter((option) => option.text);
  return [
    question,
    "",
    ...options.map((option) => `${option.correct ? "●" : "○"} ${option.text}`),
  ].join("\n").trim();
}

function manualPreviewBack(form: {
  type: ManualCardType;
  answer: string;
  options: ManualOption[];
}) {
  const answer = form.answer.trim();
  if (answer) return answer;
  if (form.type !== "single_choice" && form.type !== "multi_choice") return "";
  return form.options
    .filter((option) => option.correct && option.text.trim())
    .map((option) => option.text.trim())
    .join("；");
}

createRoot(document.getElementById("root")!).render(<App />);
