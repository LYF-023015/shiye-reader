# Android 发布清单

- [x] 本版本继续使用 `com.lyf.reading_app`，避免现有用户私有数据断开。
- [x] 已生成正式 keystore；发布前将 `.jks` 和 `key.properties` 备份到安全位置。
- [ ] 配置 GitHub Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
- [x] 版本号和构建号已更新为 `1.3.0+5`。
- [ ] 在至少一台低端机和一台主流真机验证导入、3D、EPUB、PDF、TTS、备份恢复。
- [ ] 托管隐私政策并填写 Play 数据安全表单。
- [ ] 使用 tag 触发签名 APK、AAB 和 GitHub Release。
- [ ] 在 Play Console 内部测试轨道验证 AAB 后再逐步发布。
