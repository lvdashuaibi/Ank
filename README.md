# Ank Flashcard

双端闪卡项目，当前仓库同时包含：

- `client/`：Flutter 客户端，支持登录、牌组浏览、创建卡片、联网复习、内容编辑待同步队列、AI 草稿生成
- `server/`：Go 后端，支持鉴权、牌组/卡片/复习 API、官方 FSRS 调度、PostgreSQL 存储、同步接口、AI 生成接口

## 快速启动

1. 启动 PostgreSQL、后端和 Flutter Web：

```bash
bash scripts/start_local.sh
```

2. 停止本地服务：

```bash
bash scripts/stop_local.sh
```

3. 打开预览：

```text
http://127.0.0.1:3100/
```

## 常用环境变量

参考 `.env.example`：

- `PORT`
- `JWT_SECRET`
- `STORE_DRIVER`
- `DATABASE_URL`
- `AUTO_MIGRATE`
- `API_BASE_URL`

## 当前能力

- 正式登录/注册
- PostgreSQL 持久化
- Sync push/pull
- 客户端内容编辑待同步队列
- 服务端官方 FSRS 复习调度，评分需联网提交
- 卡片搜索筛选
- AI 规则式卡片草稿生成
- iOS Simulator / macOS / Web 联调
