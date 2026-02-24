# Auto-Context Planning Document

> **Summary**: Claude Code 플러그인 - 쓸수록 프로젝트 컨텍스트가 자동 축적/정제되는 컨텍스트 엔지니어링 자동화 도구
>
> **Project**: auto-context
> **Author**: dgsw67
> **Date**: 2026-02-24
> **Status**: Draft
> **Distribution**: Claude Code Plugin (Marketplace)

---

## 1. Overview

### 1.1 Purpose

컨텍스트 엔지니어링은 AI 코딩 생산성의 핵심이지만, 세팅이 어렵고 유지가 귀찮다. Auto-Context는 이 문제를 해결하는 **Claude Code 플러그인**이다.

**사용자가 플러그인을 설치하고 Claude Code를 평소처럼 사용하기만 하면, 프로젝트 컨텍스트가 자동으로 축적/정제/주입된다.**

Peter Steinberger가 수개월간 수동으로 만든 "조직의 흉터 조직(organizational scar tissue)"을 자동화하여, 수일~수주 만에 최적화된 컨텍스트 상태에 도달하게 한다.

### 1.2 Background

**문제 정의:**
- CLAUDE.md를 직접 작성해야 한다 → 뭘 써야 하는지 모른다
- 프로젝트가 변하면 같이 업데이트해야 한다 → 귀찮아서 안 한다
- 컨텍스트의 효과를 측정할 수 없다 → "이게 도움이 되나?" 확인 불가

**정답 상태 (Reverse-Engineered from Steinberger):**
- 정제된 AGENTS.md (~800줄) - 모든 토큰이 존재 이유를 가짐
- CLI 도구들 1-2줄 설명으로 등록
- 닫힌 루프 (에이전트가 스스로 컴파일/린트/테스트/디버그)
- 파일 간 관계 맵으로 병렬 에이전트 작업 영역 분리
- 안티패턴 DB로 같은 실수 반복 방지

**핵심 인사이트:**
Steinberger의 방식은 `실패 → 본인 인지 → 수동 수정`이다. Auto-Context는 이를 `실패 → 시스템 감지 → 자동 갱신`으로 바꾼다.

### 1.3 Related Documents

- References: [Peter Steinberger's AGENTS.MD](https://github.com/steipete/agent-scripts/blob/main/AGENTS.MD)
- References: [Just Talk To It](https://steipete.me/posts/just-talk-to-it)
- References: [My Current AI Dev Workflow](https://steipete.me/posts/2025/optimal-ai-development-workflow)
- References: [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- References: [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- References: [Claude Code Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

---

## 2. Scope

### 2.1 In Scope

- [ ] Claude Code 플러그인 패키지 (plugin.json 매니페스트, 마켓플레이스 배포)
- [ ] 플러그인 hooks 기반 세션 관찰 시스템 (hooks/hooks.json)
- [ ] 컨텍스트 자동 추출 에이전트 (agents/ - agent 타입 hook 핸들러)
- [ ] 컨텍스트 생명주기 관리 (관찰 → 후보 → 컨벤션 → 퇴화)
- [ ] CLAUDE.md 자동 생성 및 점진적 갱신
- [ ] 프로젝트 초기 스캔 (X-ray) 스킬 (`/auto-context-init`)
- [ ] 상태 조회/검토 스킬 (`/auto-context-status`, `/auto-context-review`)
- [ ] 컨텍스트 효과 측정 (reward signal)

### 2.2 Out of Scope

- 병렬 에이전트 오케스트레이션 (VibeTunnel 영역)
- IDE 플러그인 (VS Code, Cursor 등)
- 클라우드 동기화 / 팀 공유
- 다른 AI 코딩 도구 지원 (Copilot, Cursor 등) - Claude Code 플러그인 전용
- 외부 API 호출 (Claude API 키 불필요 - 플러그인 내장 agent/prompt 핸들러 활용)

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | **프로젝트 초기 스캔 (X-ray)**: `/auto-context-init` 스킬 실행 시 프로젝트 구조, 기술 스택, config 파일, git 히스토리를 분석하여 초기 컨텍스트를 자동 생성 | High | Pending |
| FR-02 | **세션 관찰**: 플러그인 hooks (hooks.json)를 통해 매 세션의 파일 읽기/수정, 도구 사용, 에러/해결 쌍을 자동 기록 | High | Pending |
| FR-03 | **패턴 추출**: agent 타입 hook 핸들러가 관찰 데이터에서 반복되는 코딩 패턴, 네이밍 규칙, 파일 구조 패턴을 자동 추출 | High | Pending |
| FR-04 | **컨텍스트 생명주기**: 관찰(Observation) → 후보(Candidate) → 컨벤션(Convention) → 퇴화(Decay) 4단계 생명주기 관리 | High | Pending |
| FR-05 | **CLAUDE.md 자동 갱신**: 컨벤션으로 승격된 항목을 CLAUDE.md에 자동 반영. 기존 내용과 충돌 시 사용자에게 확인 | High | Pending |
| FR-06 | **안티패턴 감지**: 에이전트 출력을 사용자가 대폭 수정한 경우 "하지 마" 규칙으로 자동 등록 | Medium | Pending |
| FR-07 | **닫힌 루프 자동 발견**: package.json scripts, Makefile 등에서 build/test/lint 명령어를 자동 감지하여 등록 | Medium | Pending |
| FR-08 | **파일 관계 맵**: 함께 수정되는 파일 그룹을 추적하여 모듈 경계 및 의존성 맵 자동 생성 | Medium | Pending |
| FR-09 | **컨텍스트 효과 측정**: 컨텍스트 주입 전/후 사용자 수정 빈도 비교로 reward signal 생성 | Low | Pending |
| FR-10 | **스킬 인터페이스**: `/auto-context-init`, `/auto-context-status`, `/auto-context-review`, `/auto-context-reset` 슬래시 커맨드 제공 | Medium | Pending |
| FR-11 | **명시적 피드백**: 사용자가 "이거 기억해", "이거 하지 마" 등을 말하면 즉시 컨텍스트에 반영 (UserPromptSubmit hook) | High | Pending |
| FR-12 | **플러그인 매니페스트**: plugin.json으로 버전, 설명, 컴포넌트 경로 정의 | High | Pending |
| FR-13 | **마켓플레이스 배포**: GitHub 기반 마켓플레이스에 등록하여 `claude plugin install`로 설치 가능 | Medium | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| Performance | Hook command 핸들러 실행 시간 < 100ms (사용자 체감 지연 없음) | hook 실행 시간 측정 |
| Performance | Agent 핸들러 (SessionEnd 배치 분석)는 세션 종료 후 수행하므로 제한 없음 | - |
| Storage | 컨텍스트 DB < 10MB per project (.auto-context/ 디렉토리) | 파일 크기 모니터링 |
| 비침습성 | 플러그인 설치만으로 동작, 추가 설정 불필요 | 사용자 피드백 |
| 생성 품질 | 자동 생성된 CLAUDE.md가 Steinberger 수준에 80% 도달 | 수동 비교 평가 |
| 점진성 | 하나의 세션으로도 유의미한 컨텍스트 생성 | 첫 세션 후 CLAUDE.md 확인 |
| 호환성 | 기존 CLAUDE.md 보존 - 자동 생성 영역과 사용자 영역 완전 분리 | 기존 CLAUDE.md 프로젝트 테스트 |
| 이식성 | `${CLAUDE_PLUGIN_ROOT}` 기반 경로로 어디서든 동작 | 다중 환경 테스트 |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [ ] `claude plugin install auto-context@marketplace`로 설치 가능
- [ ] 설치 후 `/auto-context-init` 실행 시 프로젝트 초기 컨텍스트 자동 생성
- [ ] 3회 이상 세션 사용 후 코딩 컨벤션 자동 감지 및 등록
- [ ] 에이전트 실수 → 사용자 수정 패턴이 안티패턴 DB에 자동 등록
- [ ] CLAUDE.md가 세션마다 점진적으로 개선
- [ ] `/auto-context-status`로 축적된 컨텍스트 현황 확인 가능
- [ ] `/auto-context-review`로 후보/컨벤션 검토 및 수동 승인/거부 가능
- [ ] `/hooks` 메뉴에서 `[Plugin]` 라벨로 Auto-Context hooks 표시

### 4.2 Quality Criteria

- [ ] Hook 실행으로 인한 체감 지연 없음 (command 핸들러 < 100ms)
- [ ] 잘못된 컨벤션 자동 등록률 < 10%
- [ ] 기존 CLAUDE.md가 있는 프로젝트에서도 충돌 없이 동작
- [ ] Zero config: 플러그인 설치 후 아무 설정 없이 즉시 동작
- [ ] `claude plugin validate .` 통과

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Hook 성능 저하로 Claude Code 사용 체험 악화 | High | Medium | command 핸들러로 경량 관찰만, agent 핸들러는 SessionEnd에서만 사용 |
| 잘못된 컨벤션 자동 등록 | Medium | Medium | 3회 이상 반복 관찰 후에만 후보로 등록, `/auto-context-review`로 사용자 승인 |
| CLAUDE.md 오염 (자동 수정이 기존 내용 훼손) | High | Low | `<!-- auto-context:start -->` ~ `<!-- auto-context:end -->` 전용 섹션에만 수정 |
| 컨텍스트 폭발 (너무 많은 정보 축적) | Medium | Medium | Steinberger 원칙 "Less is More" - 토큰 예산 제한 + 퇴화 메커니즘 |
| 프라이버시 우려 (코드 내용 저장) | Medium | Low | 패턴/규칙만 저장, 실제 코드 스니펫은 저장하지 않음 |
| 플러그인 호환성 깨짐 (Claude Code 업데이트 시) | Medium | Medium | 최소 API만 사용, hook 이벤트/핸들러 타입만 의존 |
| 마켓플레이스 정책 변경 | Low | Low | GitHub 소스 기반 직접 설치도 지원 |

---

## 6. Architecture Considerations

### 6.1 배포 형태

**Claude Code Plugin** (마켓플레이스 배포)

```bash
# 설치
claude plugin install auto-context@auto-context-marketplace

# 프로젝트 단위 설치 (팀 공유)
claude plugin install auto-context@auto-context-marketplace --scope project

# 검증
claude plugin validate .
```

사용자 settings.json에 자동 등록:
```json
{
  "enabledPlugins": {
    "auto-context@auto-context-marketplace": true
  }
}
```

### 6.2 Key Architectural Decisions

| Decision | Options | Selected | Rationale |
|----------|---------|----------|-----------|
| 배포 형태 | npm package / Claude Code plugin / standalone CLI | **Claude Code Plugin (Marketplace)** | `claude plugin install`로 설치, hooks 자동 등록, 마켓플레이스 검색 가능 |
| Hook 스크립트 런타임 | Bash / Node.js / Python | **Bash + jq** | Zero dependency, 모든 환경에서 동작, command 핸들러 호환 |
| 패턴 추출 엔진 | Regex / AST 분석 / LLM 기반 | **agent 타입 hook 핸들러** | Claude Code 내장 서브에이전트 활용, 외부 API 불필요 |
| 사용자 인터랙션 | standalone CLI / Skills (슬래시 커맨드) | **Skills** | Claude Code 내에서 `/auto-context-init` 형태로 자연스러운 UX |
| 저장소 | SQLite / JSON files / LevelDB | **JSON files** | Zero dependency, 사람이 읽기 가능, git에 커밋 가능 |
| 컨텍스트 출력 | CLAUDE.md 직접 수정 / 별도 파일 / hooks injection | **CLAUDE.md 전용 마커 섹션 + .auto-context/ 디렉토리** | 사용자 영역과 자동 영역 마커로 완전 분리 |
| Hook 이벤트 | 개별 선택 / 전체 활용 | **6개 이벤트 활용** | 각 이벤트가 다른 시그널 제공 (아래 6.4 참조) |

### 6.3 System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                Auto-Context Plugin                            │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Plugin Hooks    │  │  Skills          │  │  Agents      │ │
│  │  (hooks.json)    │  │  (SKILL.md)      │  │  (.md)       │ │
│  │                  │  │                  │  │              │ │
│  │  SessionStart    │  │  /ac-init        │  │  context-    │ │
│  │  SessionEnd      │  │  /ac-status      │  │  extractor   │ │
│  │  PostToolUse     │  │  /ac-review      │  │              │ │
│  │  UserPromptSubmit│  │  /ac-reset       │  │  context-    │ │
│  │  Stop            │  │                  │  │  injector    │ │
│  │  PreCompact      │  │                  │  │              │ │
│  └───────┬─────────┘  └────────┬─────────┘  └──────┬───────┘ │
│          │                     │                    │          │
│          ▼                     ▼                    ▼          │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                   Scripts Layer                         │   │
│  │  ${CLAUDE_PLUGIN_ROOT}/scripts/                        │   │
│  │                                                        │   │
│  │  observe-tool.sh     → PostToolUse command 핸들러       │   │
│  │  detect-feedback.sh  → UserPromptSubmit command 핸들러  │   │
│  │  inject-context.sh   → SessionStart command 핸들러      │   │
│  │  track-reward.sh     → Stop command 핸들러              │   │
│  │  manage-lifecycle.sh → SessionStart command 핸들러      │   │
│  │  compact-context.sh  → PreCompact command 핸들러        │   │
│  └───────────────────────────┬────────────────────────────┘   │
│                              │                                │
│                              ▼                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              .auto-context/ (프로젝트 데이터)             │   │
│  │                                                        │   │
│  │  observations.json  ─ 관찰된 raw signal                 │   │
│  │  candidates.json    ─ 후보 패턴/컨벤션                   │   │
│  │  conventions.json   ─ 확정된 컨벤션                      │   │
│  │  anti-patterns.json ─ 안티패턴 DB                       │   │
│  │  file-relations.json─ 파일 관계 맵                      │   │
│  │  rewards.json       ─ reward signal 히스토리             │   │
│  │  config.json        ─ 플러그인 설정                      │   │
│  │  session-log.json   ─ 현재 세션 관찰 버퍼               │   │
│  └────────────────────────────────────────────────────────┘   │
│                              │                                │
│                              ▼                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              CLAUDE.md (자동 관리 섹션)                   │   │
│  │                                                        │   │
│  │  <!-- auto-context:start -->                           │   │
│  │  ## Auto-Context: Project Conventions                  │   │
│  │  ...자동 생성 컨텍스트...                                │   │
│  │  <!-- auto-context:end -->                             │   │
│  └────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────┤
│  .claude-plugin/plugin.json  ─ 플러그인 매니페스트            │
└──────────────────────────────────────────────────────────────┘

데이터 흐름:
  Session → Hooks (command) → scripts/ → .auto-context/*.json (관찰 기록)
  SessionEnd → Hooks (agent) → context-extractor → 패턴 추출 → candidates.json
  SessionStart → Hooks (command) → inject-context.sh → CLAUDE.md 갱신
  User corrections → track-reward.sh → rewards.json → Lifecycle 반영
  /ac-review → Skills → 사용자 승인/거부 → conventions.json 갱신
```

### 6.4 Hook 이벤트 매핑

| Hook Event | Handler Type | Script/Agent | 역할 |
|------------|-------------|--------------|------|
| **SessionStart** | command | `inject-context.sh` | conventions.json → CLAUDE.md 전용 섹션 갱신, 퇴화 체크 |
| **PostToolUse** (matcher: `Write\|Edit`) | command | `observe-tool.sh` | 파일 수정 이벤트를 session-log.json에 기록, 파일 관계 추적 |
| **PostToolUse** (matcher: `Bash`) | command | `observe-tool.sh` | 실행 명령어/에러를 session-log.json에 기록 |
| **UserPromptSubmit** | command | `detect-feedback.sh` | "기억해", "하지 마" 등 명시적 피드백 패턴 매칭 → 즉시 반영 |
| **Stop** | command | `track-reward.sh` | 세션 내 Write→Edit 쌍 분석 → reward signal 생성 |
| **SessionEnd** | agent | `context-extractor` | session-log.json 배치 분석 → 패턴 추출 → candidates.json 갱신 |
| **PreCompact** | command | `compact-context.sh` | 컨텍스트 압축 전 중요 정보 .auto-context/에 백업 |

### 6.5 핵심 컴포넌트 설명

#### 6.5.1 Skills (슬래시 커맨드)

| Skill | 파일 | 설명 |
|-------|------|------|
| `/ac-init` | `skills/ac-init/SKILL.md` | 프로젝트 초기 스캔 (X-ray). package.json, tsconfig, 폴더구조, git 히스토리 분석 → 초기 컨텍스트 생성 |
| `/ac-status` | `skills/ac-status/SKILL.md` | 축적된 컨텍스트 현황 표시 (관찰 수, 후보 수, 컨벤션 수, reward 추이) |
| `/ac-review` | `skills/ac-review/SKILL.md` | 후보(Candidate) 목록을 보여주고 컨벤션 승격/폐기 결정 |
| `/ac-reset` | `skills/ac-reset/SKILL.md` | .auto-context/ 초기화 및 CLAUDE.md 자동 섹션 제거 |

#### 6.5.2 Agents (서브에이전트)

| Agent | 파일 | 설명 | 사용 도구 |
|-------|------|------|----------|
| `context-extractor` | `agents/context-extractor.md` | session-log.json을 분석하여 패턴/컨벤션/안티패턴 추출. SessionEnd hook에서 agent 핸들러로 호출 | Read, Grep, Glob |
| `context-injector` | `agents/context-injector.md` | conventions.json을 읽어 CLAUDE.md 전용 섹션 생성. /ac-init 스킬에서 활용 | Read, Grep, Glob |

#### 6.5.3 Scripts (셸 스크립트)

모든 스크립트는 `${CLAUDE_PLUGIN_ROOT}/scripts/`에 위치하며, hook의 command 핸들러로 실행된다.
stdin으로 JSON 입력을 받고, stdout으로 결과를 반환한다.

| Script | 실행 시점 | 입력 (stdin JSON) | 출력 |
|--------|----------|-------------------|------|
| `observe-tool.sh` | PostToolUse | `{tool_name, tool_input, tool_output, session_id}` | session-log.json에 append |
| `detect-feedback.sh` | UserPromptSubmit | `{user_prompt, session_id}` | 피드백 감지 시 conventions.json/anti-patterns.json 즉시 갱신 |
| `inject-context.sh` | SessionStart | `{session_id, cwd}` | CLAUDE.md 전용 섹션 갱신, 퇴화 체크 수행 |
| `track-reward.sh` | Stop | `{session_id}` | session-log에서 Write→Edit 쌍 분석 → rewards.json 갱신 |
| `manage-lifecycle.sh` | SessionStart | `{session_id}` | candidates 승격 조건 확인, conventions 퇴화 확인 |
| `compact-context.sh` | PreCompact | `{session_id}` | 중요 컨텍스트 .auto-context/에 백업 |

### 6.6 플러그인 디렉토리 구조

```
auto-context/                          # 플러그인 루트 (= git repo 루트)
├── .claude-plugin/
│   └── plugin.json                    # 플러그인 매니페스트
├── skills/
│   ├── ac-init/
│   │   └── SKILL.md                   # /ac-init 슬래시 커맨드
│   ├── ac-status/
│   │   └── SKILL.md                   # /ac-status 슬래시 커맨드
│   ├── ac-review/
│   │   └── SKILL.md                   # /ac-review 슬래시 커맨드
│   └── ac-reset/
│       └── SKILL.md                   # /ac-reset 슬래시 커맨드
├── agents/
│   ├── context-extractor.md           # 패턴 추출 전문 에이전트
│   └── context-injector.md            # CLAUDE.md 갱신 전문 에이전트
├── hooks/
│   └── hooks.json                     # 모든 hook 이벤트 설정
├── scripts/
│   ├── observe-tool.sh                # PostToolUse → 관찰 기록
│   ├── detect-feedback.sh             # UserPromptSubmit → 명시적 피드백 감지
│   ├── inject-context.sh              # SessionStart → CLAUDE.md 갱신
│   ├── track-reward.sh                # Stop → reward signal 수집
│   ├── manage-lifecycle.sh            # SessionStart → 생명주기 관리
│   ├── compact-context.sh             # PreCompact → 컨텍스트 백업
│   └── lib/
│       ├── common.sh                  # 공통 함수 (JSON 읽기/쓰기, 경로 해석)
│       └── lifecycle.sh               # 생명주기 로직 (승격/퇴화 조건)
├── templates/
│   └── claude-md-section.md           # CLAUDE.md 자동 생성 섹션 템플릿
├── README.md
└── LICENSE
```

**사용자 프로젝트에 생성되는 디렉토리:**

```
user-project/
├── .auto-context/                     # 플러그인이 자동 생성/관리
│   ├── config.json                    # 프로젝트별 설정
│   ├── observations.json              # 관찰된 raw signal
│   ├── candidates.json                # 후보 패턴/컨벤션
│   ├── conventions.json               # 확정된 컨벤션
│   ├── anti-patterns.json             # 안티패턴 DB
│   ├── file-relations.json            # 파일 관계 맵
│   ├── rewards.json                   # reward signal 히스토리
│   └── session-log.json               # 현재 세션 관찰 버퍼
├── CLAUDE.md                          # 기존 + 자동 생성 섹션
│   # <!-- auto-context:start -->
│   # ...자동 관리 영역...
│   # <!-- auto-context:end -->
└── ...
```

### 6.7 plugin.json 매니페스트

```json
{
  "name": "auto-context",
  "version": "0.1.0",
  "description": "자동 컨텍스트 엔지니어링 - 쓸수록 프로젝트 컨텍스트가 축적/정제됨",
  "author": {
    "name": "dgsw67",
    "url": "https://github.com/dgsw67"
  },
  "repository": "https://github.com/dgsw67/auto-context",
  "license": "MIT",
  "keywords": ["context-engineering", "CLAUDE.md", "automation", "conventions"],
  "skills": "./skills/",
  "agents": "./agents/",
  "hooks": "./hooks/hooks.json"
}
```

### 6.8 hooks.json 설정

```json
{
  "description": "Auto-Context: 자동 컨텍스트 축적/정제 플러그인",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/manage-lifecycle.sh"
          },
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/observe-tool.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/detect-feedback.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/track-reward.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Read .auto-context/session-log.json and analyze the session data. Extract coding patterns, naming conventions, file structure patterns, and anti-patterns. Update .auto-context/candidates.json with newly detected patterns (minimum 2 occurrences in this session). Follow the lifecycle rules in .auto-context/config.json for promotion thresholds."
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compact-context.sh"
          }
        ]
      }
    ]
  }
}
```

### 6.9 마켓플레이스 전략

**Phase 1: 자체 마켓플레이스 (GitHub repo)**

```json
// .claude-plugin/marketplace.json (별도 마켓플레이스 repo에 위치)
{
  "name": "auto-context-marketplace",
  "owner": {
    "name": "dgsw67",
    "email": "dgsw67@example.com"
  },
  "plugins": [
    {
      "name": "auto-context",
      "source": {
        "source": "github",
        "repo": "dgsw67/auto-context"
      },
      "description": "자동 컨텍스트 엔지니어링 플러그인",
      "version": "0.1.0",
      "author": {
        "name": "dgsw67"
      }
    }
  ]
}
```

사용자는 마켓플레이스를 등록한 후 설치:
```json
// ~/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "auto-context-marketplace": {
      "source": {
        "source": "github",
        "repo": "dgsw67/auto-context-marketplace"
      }
    }
  }
}
```

**Phase 2: 공식 마켓플레이스 등록**

안정화 후 Anthropic 공식 마켓플레이스(anthropics/claude-plugins-official)에 PR 제출.

---

## 7. Convention Prerequisites

### 7.1 플러그인 개발 컨벤션

- [ ] `CLAUDE.md` - 본 플러그인 프로젝트의 개발 컨벤션
- [ ] Bash scripts: POSIX 호환, `set -euo pipefail`
- [ ] JSON 처리: `jq` 사용 (유일한 외부 의존성)
- [ ] Skills/Agents: Markdown 기반, YAML frontmatter 규칙 준수

### 7.2 Conventions to Define/Verify

| Category | Current State | To Define | Priority |
|----------|---------------|-----------|:--------:|
| **Script style** | missing | POSIX Bash, `set -euo pipefail`, shellcheck 통과 | High |
| **Naming** | missing | kebab-case 스크립트, kebab-case 스킬 디렉토리 | High |
| **Plugin structure** | missing | 위 6.6 구조 엄수 | High |
| **JSON schema** | missing | .auto-context/ 내 각 JSON 파일의 스키마 정의 | High |
| **Error handling** | missing | 스크립트 실패 시 exit code 규칙, stderr 로깅 | Medium |
| **Testing** | missing | BATS (Bash Automated Testing System) | Medium |

### 7.3 Environment Variables

| Variable | Purpose | Scope | Provided By |
|----------|---------|-------|-------------|
| `CLAUDE_PLUGIN_ROOT` | 플러그인 캐시 디렉토리 경로 | Plugin | Claude Code (자동 주입) |
| `CLAUDE_PROJECT_DIR` | 사용자 프로젝트 루트 경로 | Hook | Claude Code (자동 주입) |

**Note**: Auto-Context는 사용자 정의 환경변수 없이 동작한다. 위 변수들은 Claude Code가 자동으로 제공한다.

---

## 8. Reinforcement Learning Analogy (핵심 메커니즘)

이 프로젝트의 차별점인 "강화학습형 자동 개선" 메커니즘 상세:

### 8.1 State-Action-Reward 모델

```
State   = 현재 작업 파일 + 누적 컨텍스트
Action  = 어떤 컨텍스트를 CLAUDE.md에 넣을지 결정
Reward  = 사용자가 Claude 출력을 수정 없이 수락 (+1) / 대폭 수정 (-1)
Policy  = 컨텍스트 항목별 신뢰도 점수 (confidence score)
```

### 8.2 컨텍스트 생명주기 상세

```
                    ┌─ 3회 미만 관찰 ─┐
                    ▼                  │
  [Observation] ──────────────────────►│
       │                               │
       │ 3회 이상 반복                  │
       ▼                               │
  [Candidate] ─── 사용자 거부 ─────────►[Discarded]
       │          (/ac-review)
       │
       │ 자동 승격 or 사용자 승인
       ▼
  [Convention] ─── 5세션 이상 미참조 ──►[Decayed]
       │                               │
       │ 참조될 때마다 refresh          │
       │                               ▼
       └──────────────────────────────[Removed]
```

**생명주기 구현 위치:**
- Observation → Candidate: `SessionEnd` agent 핸들러 (context-extractor)
- Candidate → Convention: `manage-lifecycle.sh` (SessionStart)
- Convention → Decayed: `manage-lifecycle.sh` (SessionStart)
- 사용자 거부: `/ac-review` 스킬

### 8.3 Reward Signal 수집 방법

| Signal | 의미 | 수집 방법 | Hook/Script |
|--------|------|-----------|-------------|
| Claude Write → 사용자 Edit 없음 | 양성 (+) | Stop 시점에 session-log에서 Write 후 Edit 없는 파일 카운트 | `track-reward.sh` (Stop) |
| Claude Write → 사용자 즉시 Edit | 음성 (-) | Stop 시점에 session-log에서 Write→Edit 연속 쌍 감지 | `track-reward.sh` (Stop) |
| 사용자 "이거 기억해" 발화 | 명시적 양성 (++) | UserPromptSubmit에서 패턴 매칭 | `detect-feedback.sh` (UserPromptSubmit) |
| 사용자 "이거 하지 마" 발화 | 명시적 음성 (--) | UserPromptSubmit에서 패턴 매칭 | `detect-feedback.sh` (UserPromptSubmit) |
| 에이전트가 같은 실수 반복 | 강한 음성 (---) | SessionEnd에서 같은 에러 패턴 2회 이상 감지 | `context-extractor` agent (SessionEnd) |

---

## 9. 구현 우선순위 (Phased Rollout)

### Phase 1: Plugin Skeleton (MVP)
1. 플러그인 디렉토리 구조 생성 (plugin.json, hooks.json)
2. `/ac-init` 스킬 - 프로젝트 초기 스캔 (X-ray)
3. `inject-context.sh` - SessionStart에서 CLAUDE.md 전용 섹션 갱신
4. `.auto-context/` 디렉토리 및 JSON 스키마 정의
5. `claude plugin validate .` 통과 확인

### Phase 2: Observation
6. `observe-tool.sh` - PostToolUse command 핸들러 (파일 수정/명령어 기록)
7. `detect-feedback.sh` - UserPromptSubmit command 핸들러 (명시적 피드백)
8. `context-extractor` agent - SessionEnd 배치 분석
9. `/ac-status` 스킬

### Phase 3: Learning
10. `manage-lifecycle.sh` - 생명주기 관리 (승격/퇴화)
11. `track-reward.sh` - reward signal 수집 (Stop)
12. `/ac-review` 스킬 - 후보 검토/승인 인터페이스
13. `compact-context.sh` - PreCompact 핸들러

### Phase 4: Intelligence & Distribution
14. context-extractor agent 고도화 (코딩 컨벤션, 안티패턴 정밀 추출)
15. 스마트 주입 (상황별 컨텍스트 선택 - CLAUDE.md 토큰 예산 관리)
16. 자체 마켓플레이스 구축 및 배포
17. 공식 마켓플레이스 등록 신청

---

## 10. Next Steps

1. [ ] Design 문서 작성 (`auto-context.design.md`) - JSON 스키마, 스크립트 상세 설계
2. [ ] Phase 1 (Plugin Skeleton) 구현 시작
3. [ ] 실제 프로젝트에 dogfooding 적용
4. [ ] 자체 마켓플레이스 repo 생성

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-24 | Initial draft from brainstorm + Steinberger reverse-engineering | dgsw67 |
| 0.2 | 2026-02-24 | Claude Code Plugin 아키텍처로 전면 재설계: npm CLI → Plugin manifest, TypeScript modules → hooks.json + shell scripts + agents, CLI commands → Skills (슬래시 커맨드), 마켓플레이스 배포 전략 추가 | dgsw67 |
