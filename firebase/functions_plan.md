# Cloud Functions to write (placeholders)

| Function | Type | Purpose |
|---|---|---|
| `setStaffClaims` | admin / callable (owner) | Sets `{pid, role}` custom claims for a staff phone number. The app trusts only these claims. |
| `completeSale` | callable | Re-runs `SaleService.prepare` rules on the server (stock, FEFO, discount limit, credit limit, Rx rules) and writes stock, sale, ledger, Rx log and audit in ONE transaction. Cashiers use this instead of writing stock directly. |
| `assistant` | callable | Calls Gemini with the key from Secret Manager. Verifies auth, rate-limits per user, adds the safety system prompt, never receives patient data. |
| `anchorAuditHead` | scheduled (hourly) | Reads each device's latest audit `{n, hash}`, re-verifies the chain, stores it in `auditHeads/{device}`. Detects a device that deleted its history. |
| `dailyDemand` | Firestore trigger | Maintains `demand/{yyyy-mm-dd}` aggregates so the app never scans sales to plan reorders. |

All of them: check `request.auth.token.pid`, validate input shape, log without personal data, enable App Check enforcement.
