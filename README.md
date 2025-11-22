# BudgetApp

BudgetApp is a SwiftUI iOS client for tracking cash flow, categories, and weekly spending in Hebrew (RTL) just like the original web dashboard.

## Highlights
- Native SwiftUI layout tuned for RTL: rounded cards, capsule progress, and weekly breakdowns with right-aligned typography.
- Connects to the existing backend (`/api`) for cash flow, categories, pending transactions, and Supabase-powered reviews.
- Reusable components (cards, charts, sheets) driven by view models so new budget sections can be added quickly.

## Getting Started
1. Clone the repo and open `BudgetApp.xcodeproj` in Xcode 15+ (iOS 16 target).
2. Configure environment values via `Debug.xcconfig`/`Release.xcconfig` or a local `.env` (see `IOS_SETUP.md`).
3. Run the backend (see `/backend` folder) or point `BACKEND_BASE_URL` to your deployed API.

## Repository Layout
- `BudgetApp/` – Swift sources, components, view models, and services.
- `backend/` – Node/Express API that mirrors production endpoints.
- `docs/*.md` – Focused notes on setup, progress bar tweaks, monthly targets, and Supabase RPC checks.
- `GUIDELINES.md` – Coding guidelines for AI assistants working on the project.

## Notes
- No secrets are committed; keep `.env` local and avoid pushing `xcshareddata`.
- The UI screenshots in `Screenshot *.png` show the intended look and feel for QA.
- When working with AI assistants, ensure they follow the coding guidelines in `GUIDELINES.md` to maintain consistency and avoid common issues.

## Supabase Configuration for Development

### Setting Environment Variables in Xcode

To ensure the app can access Supabase data during development, the target reads `SUPABASE_*` keys from the bundle info dictionary:

1. Copy `Secrets/Info.plist.template` → `Secrets/Info.plist` and replace the placeholder Supabase values with your own credentials (the new file is intentionally gitignored).
2. The app also falls back to explicit environment variables or `.env` entries, so you can override the keys at runtime if needed.
3. Xcode will automatically pull the values from the info dictionary when running the app.

### Key Information:
- `SUPABASE_SECRET` or `SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY`: Used during development to bypass Row Level Security (RLS) policies
- The app looks for keys in this order: `SUPABASE_SECRET` → `SUPABASE_SECRET_KEY` → `SUPABASE_SERVICE_ROLE_KEY` → `SUPABASE_ANON_KEY`
- If none of the primary keys are available, the app will fail to initialize (for debugging purposes)
- In production, the app will use user-specific access tokens for RLS-compliant access

### Debugging Access Issues:
- Check console logs for messages like `🔐 [SUPABASE CREDS] Using key from SERVICE_ROLE`
- If you see `Using key from ANON`, please verify your credentials in `Secrets/Info.plist`
# BudgetAppProject
