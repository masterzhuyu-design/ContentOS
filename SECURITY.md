# Security policy

不要在公开 issue、PR、fixture 或日志中提交 API key、cookie、账号快照、私人笔记、真实 checkpoint、Registry、附件或本地运行数据库。

如果发现凭据泄漏、路径逃逸、未授权写入、发布/账号副作用或依赖供应链问题，请使用 GitHub 的 [Private vulnerability reporting](https://github.com/masterzhuyu-design/ContentOS/security/advisories/new)。不要先开公开 Issue；若该入口不可用，只开一个不含技术细节和凭据的 Issue，请维护者建立私下联系。

当前 release candidate 不自动登录平台、发布内容、运行调度或执行实验。适配器必须显式声明授权、读写范围、重试语义和可回读终态。
