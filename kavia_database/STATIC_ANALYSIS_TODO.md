# Database Static Analysis TODO (PostgreSQL)

Current: No SQL/migrations present. Add schema and migrations.

1) Create structure
- migrations/
  - V1__init.sql
  - V2__add_windows_tables.sql
  - etc.

2) Linting tool (sqlfluff)
- Install: pip install sqlfluff
- Config: .sqlfluff
  [sqlfluff]
  dialect = postgres
  max_line_length = 100
  exclude_rules = L009

- Run:
  sqlfluff lint migrations/ --dialect postgres
  sqlfluff fix migrations/ --dialect postgres  # caution, review diffs

3) Best practices to enforce
- snake_case identifiers
- explicit schemas (e.g., public or app schema)
- not null + sensible defaults
- foreign keys with indexes
- avoid SELECT * in views/functions
- use check constraints for enumerations

4) Optional validation in CI
- Spin up ephemeral Postgres and apply migrations (Flyway/Liquibase)
- Validate schema, run smoke queries
