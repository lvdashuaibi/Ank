# Ank Flutter Client

Flutter 客户端用于牌组管理、卡片编辑、Card DSL 导入和联网复习。

## Notes

- 复习评分必须联网提交，由服务端官方 FSRS 引擎计算下一次到期时间。
- 本地缓存用于启动加速和弱网查看。
- 内容编辑仍可进入待同步队列；复习排期不在客户端离线计算。

## Development

```bash
flutter test -r compact
flutter analyze
```

Run with the repository root startup script when you need the backend:

```bash
bash ../scripts/start_local.sh
```
