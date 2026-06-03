const apiBase = "/api/v1";
const state = {
  token: localStorage.getItem("ank_token") || "",
  user: JSON.parse(localStorage.getItem("ank_user") || "null"),
  decks: [],
  cards: [],
  selectedDeckId: localStorage.getItem("ank_deck_id") || "",
};

const $ = (id) => document.getElementById(id);

function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.classList.remove("hidden");
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => el.classList.add("hidden"), 3200);
}

async function api(path, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const response = await fetch(`${apiBase}${path}`, { ...options, headers });
  if (!response.ok) {
    let message = `${response.status} ${response.statusText}`;
    try {
      const body = await response.json();
      message = body.error || message;
    } catch (_) {}
    throw new Error(message);
  }
  if (response.status === 204) return null;
  return response.json();
}

function setBusy(form, busy) {
  for (const el of form.querySelectorAll("button, input, textarea")) {
    el.disabled = busy;
  }
}

function saveSession(token, user) {
  state.token = token;
  state.user = user;
  localStorage.setItem("ank_token", token);
  localStorage.setItem("ank_user", JSON.stringify(user));
  renderShell();
}

function clearSession() {
  state.token = "";
  state.user = null;
  state.selectedDeckId = "";
  state.decks = [];
  state.cards = [];
  localStorage.removeItem("ank_token");
  localStorage.removeItem("ank_user");
  localStorage.removeItem("ank_deck_id");
  renderShell();
}

function renderShell() {
  const signedIn = Boolean(state.token);
  $("authPanel").classList.toggle("hidden", signedIn);
  $("appPanel").classList.toggle("hidden", !signedIn);
  $("logoutButton").classList.toggle("hidden", !signedIn);
  $("sessionLabel").textContent = signedIn
    ? `${state.user?.display_name || state.user?.email || "已登录"}`
    : "未登录";
}

function renderDecks() {
  const list = $("deckList");
  list.innerHTML = "";
  if (state.decks.length === 0) {
    list.innerHTML = `<p class="muted">暂无牌组，先新建一个。</p>`;
    return;
  }
  for (const deck of state.decks) {
    const item = document.createElement("div");
    item.className = `deck-item ${deck.id === state.selectedDeckId ? "active" : ""}`;
    item.innerHTML = `
      <strong>${escapeHtml(deck.name)}</strong>
      <p class="muted">${escapeHtml(deck.description || "无说明")}</p>
      <span class="pill">新卡/天 ${deck.new_cards_per_day ?? 20}</span>
      <span class="pill">最大复习 ${deck.max_reviews_per_day ?? 200}</span>
    `;
    item.onclick = () => selectDeck(deck.id);
    list.appendChild(item);
  }
}

function renderCards() {
  const deck = state.decks.find((item) => item.id === state.selectedDeckId);
  $("deckTitle").textContent = deck ? deck.name : "请选择牌组";
  $("deckMeta").textContent = deck ? (deck.description || "当前牌组") : "卡片会显示在下方";
  $("cardCountLabel").textContent = `${state.cards.length} 张`;
  const list = $("cardList");
  list.innerHTML = "";
  if (!deck) {
    list.innerHTML = `<p class="muted">选择左侧牌组后查看卡片。</p>`;
    return;
  }
  if (state.cards.length === 0) {
    list.innerHTML = `<p class="muted">这个牌组还没有卡片。</p>`;
    return;
  }
  for (const card of state.cards) {
    const item = document.createElement("article");
    item.className = "card-item";
    item.innerHTML = `
      <h3>${escapeHtml(card.title || card.front || "未命名卡片")}</h3>
      <pre>${escapeHtml(card.front || card.content || "")}</pre>
      <pre>${escapeHtml(card.back || "")}</pre>
      ${(card.tags || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
      <span class="pill">${card.study_enabled ? "已加入背诵" : "未加入背诵"}</span>
    `;
    list.appendChild(item);
  }
}

function renderDrafts(drafts) {
  const root = $("aiDrafts");
  root.innerHTML = "";
  if (!drafts || drafts.length === 0) return;
  for (const [index, draft] of drafts.entries()) {
    const item = document.createElement("article");
    item.className = "draft-item";
    item.innerHTML = `
      <h3>${escapeHtml(draft.title || `草稿 ${index + 1}`)}</h3>
      <pre>${escapeHtml(draft.front || draft.content || "")}</pre>
      <pre>${escapeHtml(draft.back || "")}</pre>
      ${(draft.tags || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
      <button data-index="${index}">保存这张</button>
    `;
    item.querySelector("button").onclick = () => saveDraft(draft);
    root.appendChild(item);
  }
}

async function loadDecks() {
  const body = await api("/decks");
  state.decks = body.items || [];
  if (!state.decks.some((deck) => deck.id === state.selectedDeckId)) {
    state.selectedDeckId = state.decks[0]?.id || "";
  }
  localStorage.setItem("ank_deck_id", state.selectedDeckId);
  renderDecks();
  await loadCards();
}

async function loadCards() {
  if (!state.selectedDeckId) {
    state.cards = [];
    renderCards();
    return;
  }
  const body = await api(`/decks/${state.selectedDeckId}/cards`);
  state.cards = body.items || [];
  renderCards();
}

async function selectDeck(deckId) {
  state.selectedDeckId = deckId;
  localStorage.setItem("ank_deck_id", deckId);
  renderDecks();
  await loadCards();
}

function cardPayloadFromDraft(draft) {
  return {
    title: draft.title || "AI 草稿",
    content: draft.content || "",
    front: draft.front || draft.content || "",
    back: draft.back || "",
    tags: draft.tags || [],
    note: draft.note || "",
    source: "web",
    study_enabled: true,
  };
}

async function saveDraft(draft) {
  if (!state.selectedDeckId) return toast("请先选择牌组");
  await api(`/decks/${state.selectedDeckId}/cards`, {
    method: "POST",
    body: JSON.stringify(cardPayloadFromDraft(draft)),
  });
  toast("草稿已保存");
  await loadCards();
}

function parseTags(value) {
  return value.split(/[,，;；\s]+/).map((tag) => tag.trim()).filter(Boolean);
}

function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

$("authForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const action = event.submitter?.dataset.action || "login";
  const form = event.currentTarget;
  setBusy(form, true);
  try {
    const body = await api(`/auth/${action}`, {
      method: "POST",
      body: JSON.stringify({
        email: $("emailInput").value.trim(),
        password: $("passwordInput").value,
        display_name: $("displayNameInput").value.trim() || "Web User",
      }),
    });
    saveSession(body.access_token, body.user);
    toast(action === "register" ? "注册成功" : "登录成功");
    await loadDecks();
  } catch (error) {
    toast(error.message);
  } finally {
    setBusy(form, false);
  }
});

$("deckForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  setBusy(form, true);
  try {
    const deck = await api("/decks", {
      method: "POST",
      body: JSON.stringify({
        name: $("deckNameInput").value.trim(),
        description: $("deckDescriptionInput").value.trim(),
        color: "#2d756f",
        icon: "📚",
        review_order: "sequential",
        new_cards_per_day: 20,
        max_reviews_per_day: 200,
      }),
    });
    form.reset();
    state.selectedDeckId = deck.id;
    await loadDecks();
    toast("牌组已创建");
  } catch (error) {
    toast(error.message);
  } finally {
    setBusy(form, false);
  }
});

$("cardForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!state.selectedDeckId) return toast("请先选择牌组");
  const form = event.currentTarget;
  setBusy(form, true);
  try {
    await api(`/decks/${state.selectedDeckId}/cards`, {
      method: "POST",
      body: JSON.stringify({
        title: $("cardTitleInput").value.trim(),
        content: $("cardFrontInput").value.trim(),
        front: $("cardFrontInput").value.trim(),
        back: $("cardBackInput").value.trim(),
        tags: parseTags($("cardTagsInput").value),
        source: "web",
        study_enabled: $("studyEnabledInput").checked,
      }),
    });
    form.reset();
    $("studyEnabledInput").checked = true;
    await loadCards();
    toast("卡片已保存");
  } catch (error) {
    toast(error.message);
  } finally {
    setBusy(form, false);
  }
});

$("aiForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  setBusy(form, true);
  try {
    const body = await api("/ai/generate", {
      method: "POST",
      body: JSON.stringify({
        topic: $("aiTopicInput").value.trim() || $("deckTitle").textContent,
        context: $("aiContextInput").value.trim(),
        card_count: Number($("aiCountInput").value || 4),
        difficulty: "medium",
        policy: {
          atomicity_level: "strict",
          answer_style: "one_sentence",
          max_answer_chars: 100,
          rules: "优先生成符合 DSL 的选择题或原子问答卡，题干聚焦单一知识点。",
        },
      }),
    });
    renderDrafts(body.items || []);
    toast(`已生成 ${(body.items || []).length} 张草稿`);
  } catch (error) {
    toast(error.message);
  } finally {
    setBusy(form, false);
  }
});

$("refreshButton").onclick = () => loadDecks().catch((error) => toast(error.message));
$("logoutButton").onclick = clearSession;

renderShell();
if (state.token) {
  loadDecks().catch((error) => {
    toast(error.message);
    if (/unauthorized|token|401/i.test(error.message)) clearSession();
  });
}
