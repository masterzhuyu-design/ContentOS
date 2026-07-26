# 更新与用户覆盖层

## 三层

1. `core/`：发行版规则和 schema；
2. `.contentos/local-overrides.json`：本机功能偏好和预算覆盖；
3. `vault/`：用户数据。

更新 Core 时不得覆盖后两层。

## 推荐更新流程

1. 备份或提交当前工作区；
2. 查看新版 module registry 和迁移说明；
3. 在临时目录初始化新版；
4. 比较 Core Interface 和 schema；
5. 运行干净安装与旧数据只读兼容测试；
6. 用户确认后替换 Core；
7. 回读用户配置、vault 和 checkpoint。

## 柔性预算覆盖

用户可以在 local overrides 中修改 soft target 和 advisory ceiling，但：

- 不得关闭 semantic truncation guard；
- 不得让预算自动删除承重信息；
- 增加预算不等于增加权限；
- 高成本配置应在真实 workload 中观察收益。

## 升级回退

Core 更新应有版本标签。回退只回退 Core 和 profiles，不回退或删除用户 vault。schema 有破坏性变化时必须提供迁移与逆向恢复说明。
