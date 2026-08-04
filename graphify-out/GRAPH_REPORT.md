# Graph Report - /root/project/sh/vps-security  (2026-08-03)

## Corpus Check
- Corpus is ~10,896 words - fits in a single context window. You may not need a graph.

## Summary
- 98 nodes · 287 edges · 8 communities
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Features & Module Docs
- Core Security Modules
- Script Scaffolding & Constants
- Error-Handling Tests
- Integration Tests
- Startup, Rollback & Entry Point
- Input Validation
- Menu & Reporting

## God Nodes (most connected - your core abstractions)
1. `main()` - 22 edges
2. `vps-security.sh - main VPS hardening script` - 20 edges
3. `header()` - 16 edges
4. `module_ssh_keys()` - 16 edges
5. `info()` - 15 edges
6. `module_ssh_port()` - 15 edges
7. `log()` - 14 edges
8. `success()` - 14 edges
9. `warn()` - 14 edges
10. `module_create_user()` - 14 edges

## Surprising Connections (you probably didn't know these)
- `init_paths()` --calls--> `log()`  [EXTRACTED]
  vps-security.sh → vps-security.sh  _Bridges community 5 → community 1_
- `error()` --calls--> `log()`  [EXTRACTED]
  vps-security.sh → vps-security.sh  _Bridges community 1 → community 6_
- `main()` --calls--> `error()`  [EXTRACTED]
  vps-security.sh → vps-security.sh  _Bridges community 6 → community 5_
- `show_menu()` --calls--> `header()`  [EXTRACTED]
  vps-security.sh → vps-security.sh  _Bridges community 1 → community 7_
- `safe_exec()` --calls--> `error_handler()`  [EXTRACTED]
  vps-security.sh → vps-security.sh  _Bridges community 1 → community 2_

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Security hardening module suite of vps-security.sh** — readme_module_user, readme_module_ufw, readme_module_fail2ban, readme_module_ssh_port, readme_module_ssh_keys, readme_module_auto_updates, readme_module_ssh_audit, readme_module_aide, readme_module_rkhunter, readme_module_root_block [INFERRED 0.95]
- **Change safety and recovery mechanism (backup, rollback, logging)** — readme_backup, readme_rollback, readme_logging [INFERRED 0.85]
- **Test suite for vps-security.sh** — readme_test_error_handling_sh, readme_test_integration_sh, readme_vps_security_sh [INFERRED 0.85]

## Communities (8 total, 0 thin omitted)

### Community 0 - "Features & Module Docs"
Cohesion: 0.10
Nodes (23): Automatic backups before each change, Dry-run demo mode (--dry-run), Email notifications (AIDE and rkhunter reports), Error handling (retry/skip/back-to-menu/exit), Logging to /var/log/vps-security-*.log, Module 8: AIDE - file integrity monitoring (IDS), Module 6: Auto updates - unattended-upgrades (security only), Module 3: Fail2ban - block IPs after failed logins (+15 more)

### Community 1 - "Core Security Modules"
Cohesion: 0.45
Nodes (23): backup_file(), confirm(), dry_run_or_exec(), error_handler(), header(), info(), log(), module_aide() (+15 more)

### Community 2 - "Script Scaffolding & Constants"
Cohesion: 0.12
Nodes (12): BLUE, BOLD, CYAN, GREEN, NC, ORIGINAL_SSH_PORT, RED, safe_exec() (+4 more)

### Community 3 - "Error-Handling Tests"
Cohesion: 0.35
Nodes (11): check_package(), check_service(), error(), fail(), pass(), section(), test-error-handling.sh script, test_func() (+3 more)

### Community 4 - "Integration Tests"
Cohesion: 0.52
Nodes (6): fail(), pass(), section(), setup(), test-integration.sh script, teardown()

### Community 5 - "Startup, Rollback & Entry Point"
Cohesion: 0.38
Nodes (7): check_root(), detect_os(), do_rollback(), init_paths(), main(), vps-security.sh script, show_ascii_critical()

### Community 6 - "Input Validation"
Cohesion: 0.33
Nodes (6): ask_port(), error(), run_tests(), validate_email(), validate_port(), validate_username()

### Community 7 - "Menu & Reporting"
Cohesion: 0.67
Nodes (3): divider(), show_menu(), show_report()

## Knowledge Gaps
- **22 isolated node(s):** `SCRIPT_VERSION`, `SCRIPT_NAME`, `SCRIPT_URL`, `ORIGINAL_SSH_PORT`, `RED` (+17 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `main()` connect `Startup, Rollback & Entry Point` to `Core Security Modules`, `Script Scaffolding & Constants`, `Input Validation`, `Menu & Reporting`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `vps-security.sh - main VPS hardening script` (e.g. with `test-error-handling.sh - error-handling tests` and `test-integration.sh - integration tests`) actually correct?**
  _`vps-security.sh - main VPS hardening script` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `SCRIPT_VERSION`, `SCRIPT_NAME`, `SCRIPT_URL` to the rest of the system?**
  _22 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Features & Module Docs` be split into smaller, more focused modules?**
  _Cohesion score 0.09881422924901186 - nodes in this community are weakly interconnected._
- **Should `Script Scaffolding & Constants` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._