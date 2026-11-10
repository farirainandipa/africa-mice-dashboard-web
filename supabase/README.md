# Database

This site uses the shared Supabase project `upzkvszgoqhoefkiwoep`, which also
backs farirainandipa.co.zw.

The dashboard now lives in this repository, so new pipeline migrations are kept
here in `supabase/migrations/`. Name each file `<version>_<name>.sql`, using the
version the project records in `supabase_migrations.schema_migrations` when the
migration is applied. Never edit old ones. After applying, run the Supabase
security advisor.

The earlier schema, seed data and migrations (001 to 023, before the move) remain
in the **farirainandipa-web** repository under `supabase/migrations/` for
reference. See CLAUDE.md for the access model.
