# GitHub Secrets Setup for Bucks Sync

Go to: https://github.com/shafeeqduddiyanda/bucks.global/settings/secrets/actions

| Secret Name       | Description                        | Status        |
|-------------------|------------------------------------|---------------|
| FRED_API_KEY      | St. Louis Fed FRED API key         | ✓ Configured  |
| METALS_API_KEY    | metals.dev API key                 | ✓ Configured  |
| COMTRADE_API_KEY  | UN Comtrade subscription key       | ⚠ Pending     |
| DATAGOV_API_KEY   | data.gov.in API key                | ✓ Configured  |

## COMTRADE_API_KEY

Requires a UN Comtrade subscription. Once you have the key:
1. Go to the secrets page linked above
2. Click "New repository secret"
3. Name: `COMTRADE_API_KEY`, Value: your subscription key

## Running the workflow

1. Go to the Actions tab in GitHub
2. Click "Bucks Intelligence Data Sync"
3. Click "Run workflow" → Run manually once to test
4. Check that the `data/` folder is created and populated
