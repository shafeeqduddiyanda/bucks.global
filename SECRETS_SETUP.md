# GitHub Secrets Setup for Bucks Sync

Go to: https://github.com/shafeeqduddiyanda/bucks.global/settings/secrets/actions

| Secret Name                  | Description                          | Status        |
|------------------------------|--------------------------------------|---------------|
| FRED_API_KEY                 | St. Louis Fed FRED API key           | ✓ Configured  |
| METALS_API_KEY               | metals.dev API key                   | ✓ Configured  |
| COMTRADE_API_KEY             | UN Comtrade primary key              | ✓ Configured  |
| COMTRADE_API_KEY_SECONDARY   | UN Comtrade secondary/fallback key   | ✓ Configured  |
| DATAGOV_API_KEY              | data.gov.in API key                  | ✓ Configured  |

## Comtrade Key Fallback

The sync script uses `COMTRADE_API_KEY` (primary) first. If it is not set,
it automatically falls back to `COMTRADE_API_KEY_SECONDARY`.

## Running the workflow

1. Go to the Actions tab in GitHub
2. Click "Bucks Intelligence Data Sync"
3. Click "Run workflow" → Run manually once to test
4. Check that the `data/` folder is created and populated
