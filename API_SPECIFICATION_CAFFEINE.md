# Caffeine System - Server API Specification

## Overview
The Caffeine system manages user balance and deducts charges for AI operations. All balance changes must be server-side validated and applied atomically.

---

## 1. Caffeine Deduction (核心端点)

### Endpoint
```
POST /api/caffeine/deduct
Authorization: Bearer {user_token}
Content-Type: application/json
```

### Request
```json
{
  "package_id": "ingredient_scan" | "recipe_generate" | "image_generate",
  "amount": 35,
  "request_id": "uuid_v4_idempotency_key"
}
```

### Response (Success)
```json
{
  "success": true,
  "auth_token": "caffeineAuth_xyz123_timestamps",
  "new_balance": {
    "percentage": 205,
    "cups": 2.05
  },
  "deducted_at": "2026-02-14T10:30:00Z"
}
```

### Response (Insufficient Balance)
```json
{
  "success": false,
  "error_code": "INSUFFICIENT_BALANCE",
  "required": 35,
  "current": 20,
  "suggested_reward": {
    "type": "ad_watch",
    "amount": 60,
    "description": "Watch an ad to earn 60% more"
  }
}
```

### Response (Rate Limited)
```json
{
  "success": false,
  "error_code": "RATE_LIMITED",
  "message": "You have exceeded daily free request limit",
  "retry_after_seconds": 3600
}
```

---

## 2. Caffeine Reward (광고 보상)

### Endpoint
```
POST /api/caffeine/reward
Authorization: Bearer {user_token}
Content-Type: application/json
```

### Request
```json
{
  "reward_type": "rewarded_ad" | "purchase",
  "ad_platform": "admob" | "firebase" (optional, only for ads),
  "ad_unit_id": "ca-app-pub-xxxxx..." (optional),
  "rewarded_at": "2026-02-14T10:30:00Z",
  "request_id": "uuid_v4_idempotency_key"
}
```

### Response (Success)
```json
{
  "success": true,
  "reward_amount": 60,
  "new_balance": {
    "percentage": 260,
    "cups": 2.6
  },
  "added_at": "2026-02-14T10:30:00Z"
}
```

### Response (Fraud Detection)
```json
{
  "success": false,
  "error_code": "FRAUD_SUSPECTED",
  "message": "Ad reward already claimed or user played ad too quickly"
}
```

---

## 3. Balance Inquiry

### Endpoint
```
GET /api/caffeine/balance
Authorization: Bearer {user_token}
```

### Response
```json
{
  "percentage": 240,
  "cups": 2.4,
  "last_updated": "2026-02-14T10:30:00Z",
  "daily_free_requests": {
    "remaining": 2,
    "reset_at": "2026-02-15T00:00:00Z"
  },
  "ad_watch_limit": {
    "remaining": 4,
    "reset_at": "2026-02-15T00:00:00Z"
  }
}
```

---

## 4. Transaction History

### Endpoint
```
GET /api/caffeine/history?limit=50&offset=0
Authorization: Bearer {user_token}
```

### Response
```json
{
  "transactions": [
    {
      "id": "txn_xyz123",
      "type": "deduct",
      "package_id": "ingredient_scan",
      "amount": 35,
      "balance_after": 205,
      "timestamp": "2026-02-14T10:30:00Z",
      "status": "completed"
    },
    {
      "id": "txn_xyz124",
      "type": "reward",
      "reward_type": "rewarded_ad",
      "amount": 60,
      "balance_after": 265,
      "timestamp": "2026-02-14T10:25:00Z",
      "status": "completed"
    }
  ],
  "total": 150,
  "limit": 50,
  "offset": 0
}
```

---

## 5. Validation Rules

### Server-Side Checks
1. **Atomicity**: Balance deduction must be atomic (all-or-nothing)
2. **Duplicate Prevention**: Use `request_id` (idempotency key) to prevent duplicate charges
3. **Rate Limiting**: 
   - Free requests per day: 3 (configurable)
   - Ad rewards per day: 5 (configurable)
   - Cooldown between ads: 30 seconds (configurable)
4. **Fraud Detection**:
   - Ad watched too quickly (< 30 seconds)
   - Same user claiming same ad multiple times
   - Unusual patterns (e.g., 100 requests in 5 minutes)

### Client-Side Checks (UX Only)
1. Show warning if balance < next operation cost
2. Disable AI buttons if balance = 0
3. Suggest reward options when balance insufficient

---

## 6. Error Codes

| Code | Meaning | Client Action |
|------|---------|---------------|
| `INSUFFICIENT_BALANCE` | Not enough caffeine | Show charge panel with reward options |
| `RATE_LIMITED` | Daily limit exceeded | Disable AI button until tomorrow |
| `AUTH_FAILED` | Invalid/expired token | Redirect to login |
| `FRAUD_SUSPECTED` | Suspicious activity | Block user temporarily + alert |
| `SERVER_ERROR` | Internal server error | Retry with exponential backoff |
| `INVALID_PACKAGE_ID` | Unknown package | Log error, refresh config |

---

## 7. Client Implementation Checklist

- [ ] Initialize CaffeineService on app startup
- [ ] Load caffeine_config.json for package definitions
- [ ] Show CaffeineConfirmDialog before AI operation
- [ ] Call `/api/caffeine/deduct` with request_id (UUID)
- [ ] Use returned auth_token for subsequent AI API calls
- [ ] Display CaffeineBalancePanel on main screen
- [ ] Implement ad reward flow → `/api/caffeine/reward`
- [ ] Cache balance locally but refresh on app foreground
- [ ] Handle insufficient balance gracefully

---

## 8. Migration Path

**Phase 1 (Current)**
- Mock balance (local only)
- Confirm dialogs + UI structure

**Phase 2 (Backend Integration)**
- Connect to real server API
- Implement user authentication
- Set up balance DB schema

**Phase 3 (Monetization)**
- Enable RewardedAd SDK (AdMob)
- Implement in-app purchase (Google Play Billing)
- Monitor fraud patterns

**Phase 4 (Analytics)**
- Track conversion rates (free → ad → purchase)
- Analyze caffeine spend patterns
- Optimize pricing & rewards

---

## 9. Sample Curl Commands

### Deduct Caffeine
```bash
curl -X POST https://api.iTNe.com/api/caffeine/deduct \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "package_id": "ingredient_scan",
    "amount": 35,
    "request_id": "550e8400-e29b-41d4-a716-446655440000"
  }'
```

### Claim Reward
```bash
curl -X POST https://api.iTNe.com/api/caffeine/reward \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "reward_type": "rewarded_ad",
    "ad_platform": "admob",
    "rewarded_at": "2026-02-14T10:30:00Z",
    "request_id": "660e8400-e29b-41d4-a716-446655440001"
  }'
```

### Get Balance
```bash
curl -X GET https://api.iTNe.com/api/caffeine/balance \
  -H "Authorization: Bearer {token}"
```

---

**Last Updated**: Feb 14, 2026
**Status**: Ready for Backend Integration
