# Git 协作规范

> 适用仓库：`hardware_design`（GitHub 私有仓库 `Y-LarK/hardware_design`，SSH 协议）
> 成员：2 人（Fedora 44 + Vivado 2023.2 ／ Windows + Vivado 2019.1）
> 建立日期：2026-10-16
> 相关文档：[DESIGN.md](DESIGN.md) §6.1（工程管理）、§6（目录结构）

---

## 1. 分支模型

本项目规模小（2 人、约 9 周），采用**单人单分支 + 短生命周期特性分支**的轻量模型：

| 分支 | 用途 | 生命周期 |
|---|---|---|
| `main` | 唯一主干，始终保持可综合、可仿真 | 永久 |
| `feat/<主题>` | 一个功能/一次大改动一个分支（如 `feat/pipeline-forwarding`） | 合并后删除 |

**规则**：

- 小改动（文档、注释、单文件修正）直接在 `main` 上做，直接 push
- 大改动（新模块、流水线改造、可能影响别人仿真的改动）**必须开特性分支**，自测通过后再合回
- **禁止 force push 到 `main`**；特性分支自己的 rebase 随意
- 合并方式用 **squash merge 或 fast-forward 均可**，但一个特性进入 main 后应是一个（或少数几个）干净的提交

## 2. Commit Message 规范（Conventional Commits）

格式：

```
<type>: <一句话中文描述（≤50 字）>

<可选正文：空一行后写动机、要点，每行 ≤72 字>
```

**type 取值**：

| type | 用途 | 本项目示例 |
|---|---|---|
| `feat` | 新功能/新模块 | `feat: 五级流水线数据转发单元` |
| `fix` | 修复 bug | `fix: 转发优先级 EX/MEM 先于 MEM/WB` |
| `refactor` | 重构（不改行为） | `refactor: 源码迁出工程改为引用式` |
| `perf` | 性能优化 | `perf: 除法提前结束减少平均周期` |
| `docs` | 仅文档 | `docs: 回填上板验证结果` |
| `test` | 测试/testbench | `test: 补乘除边界用例（除零、-2^31/-1）` |
| `chore` | 构建/工具/杂项 | `chore: 初始化仓库与 .gitignore` |

**硬性要求**：

1. 中文描述、type 用英文——与仓库现状一致
2. **一次提交只做一件事**：修 bug 的提交不捎带格式化，加功能的提交不捎带删文件
3. 提交前 `git diff --staged` 过目一遍，不提交没看过的内容
4. 不在 message 里写「修改了一些文件」「update」这类无信息量描述

**反例**（仓库里已出现过，引以为戒）：

```
add some text in DESIGN.md     ← 无 type、无信息量
```

## 3. 提交内容边界（什么能进 git）

**原则：仓库只存「源」，不存「工程」。** 详见 DESIGN.md §6.1。

**✅ 提交**：

- `rtl_single_cycle/`、`rtl/`（流水线阶段）的全部 `.v`
- `constraints/` 的 `.xdc`
- `sim/` 的 testbench
- `tests/` 的汇编源与 `hex/` 下的 `.hex`/`.mem`（白名单已放行）
- `design/`、`doc/` 的文档与课程资料

**❌ 禁止提交**（`.gitignore` 已拦截，但 `git add -f` 可绕过，别用）：

- `*.xpr` 工程文件、`*.cache/`、`*.runs/`、`*.hw/`、`*.sim/`、`*.ip_user_files/`
- `*.bit`、`*.jou`、`*.log`、`*.rpt`、`*.wdb` 等生成物
- `.Xil/`、`*.vcd`、仿真临时产物

**每次 add 前自查**：

```bash
git status                    # 看有没有意外文件
git add -n <路径>             # 干跑：确认会加进什么
git diff --staged --stat      # 提交前最后过目
```

> ⚠️ Vivado 的「目录即工程」形态生成物**不带点前缀**（`cpu_single.cache/` 等），靠 `.gitignore` 的 `*.cache/` 模式拦截。若新建工程用了别的名字，`git status` 里出现可疑目录时先补 `.gitignore` 再 add，不要绕过。

## 4. 源文件编码

- **新文件一律 UTF-8**（RTL 注释、文档、脚本）
- 旧文件（Windows 侧创建）部分是 GBK 注释：git 按字节存不受影响，但**编辑旧文件时别让编辑器整文件转码**（会造成全文件 diff，淹没真实改动）。VS Code 右下角确认编码；动了哪行就只改哪行
- 行尾：仓库**不设** `.gitattributes` 的 autocrlf 转换（跨 Windows/Linux 双向转换反而制造 diff），提交什么字节就存什么字节。Windows 侧编辑器若自动转 CRLF，提交前注意 `git diff` 是否出现全行变更

## 5. 推拉纪律（避免分叉）

**push 前必做**：

```bash
git pull --rebase origin main
git push
```

- 已发生过一次「网页编辑 vs 本地提交」的分叉（`09ecea5`），`--rebase` 是标准处理方式；分叉了不要用普通 `git pull`（会产生 merge commit 污染历史），更不要 force push
- 队友在 GitHub 网页上改文档也 allowed，但改完**自己本地拉取后再继续工作**

**每天开工第一件事**：

```bash
git pull --rebase origin main
```

**收工前**：当天的工作要么 commit 完 push，要么明确说明留在工作区的原因——不留「改了一半没提交也没说」的状态过夜。

## 6. 冲突处理

1. `git pull --rebase` 冲突时，逐文件解决后 `git add <文件>` + `git rebase --continue`
2. `DESIGN.md` 是两人高频编辑区，**改动前先 pull**，改完尽快 push，缩短窗口
3. 大段重构（如挪目录）提前在群里说一声，避免与对方并行改动撞车

## 7. 敏感信息

- 仓库内**禁止出现**任何密钥、token、密码（GitHub token、学校账号等）
- 目前仓库无敏感文件；若以后需要放配置，用模板文件（`config.example` + `.gitignore` 掉真文件）

## 8. 常用操作速查

```bash
# 开工
git pull --rebase origin main

# 开特性分支
git switch -c feat/pipeline-forwarding

# 干跑确认要提交什么
git add -n rtl_single_cycle/
git status

# 提交（规范的中文 message）
git add <文件>
git commit -m "feat: xxx"

# 收工
git pull --rebase origin main
git push

# 误 add 了生成物（还没 commit）
git restore --staged <文件>

# 误 commit（还没 push）
git commit --amend   # 改 message 或内容

# 查看历史
git log --oneline --graph -15
```

---

*本规范随项目进展修订；修改时在 commit message 里用 `docs:` 前缀。*
