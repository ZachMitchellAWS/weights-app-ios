# Apple Sign In Backend Integration Guide

This document provides the backend team with the necessary context to implement the Apple Sign In authentication endpoint.

## Overview

The iOS app implements Sign in with Apple using Apple's `AuthenticationServices` framework. When a user authenticates via Apple, the app receives:

1. **Identity Token** - A JWT signed by Apple containing user identity claims
2. **Authorization Code** - A single-use code for server-to-server token exchange
3. **User ID** - A stable, app-scoped identifier for the user
4. **Email** (first sign-in only) - The user's email address
5. **Full Name** (first sign-in only) - The user's name components

## Expected API Endpoint

### POST `/auth/apple-signin`

#### Request Body

```json
{
  "identityToken": "eyJraWQiOi...",
  "authorizationCode": "c1234567890abcdef...",
  "email": "user@example.com",
  "fullName": "John Doe"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `identityToken` | string | Yes | JWT from Apple (see verification below) |
| `authorizationCode` | string | Yes | Single-use code, valid for 5 minutes |
| `email` | string | No | Only provided on FIRST authorization |
| `fullName` | string | No | Only provided on FIRST authorization |

#### Response (Success)

Should match the existing `AuthResponse` format:

```json
{
  "accessToken": "eyJ...",
  "refreshToken": "refresh_token_here",
  "userId": "user-uuid",
  "emailAddress": "user@example.com",
  "accessTokenExpiresIn": 3600,
  "refreshTokenExpiresIn": 2592000
}
```

#### Response (Error)

```json
{
  "message": "Error description"
}
```

## Identity Token (JWT) Structure

The identity token is a JWT with the following structure:

### Header
```json
{
  "kid": "W6WcOKB",
  "alg": "RS256"
}
```

### Payload
```json
{
  "iss": "https://appleid.apple.com",
  "aud": "com.yourcompany.WeightApp",
  "exp": 1234567890,
  "iat": 1234567890,
  "sub": "001234.abcdef1234567890.1234",
  "at_hash": "...",
  "email": "user@example.com",
  "email_verified": "true",
  "is_private_email": "false",
  "auth_time": 1234567890,
  "nonce_supported": true
}
```

### Important Claims

| Claim | Description |
|-------|-------------|
| `iss` | Always `https://appleid.apple.com` |
| `aud` | Your app's bundle identifier |
| `sub` | User's unique identifier (stable per app) |
| `email` | User's email (may be private relay address) |
| `is_private_email` | `"true"` if using Apple's private email relay |

## Token Verification Process

### Step 1: Fetch Apple's Public Keys

```
GET https://appleid.apple.com/auth/keys
```

Response contains JWKS (JSON Web Key Set) used to verify the JWT signature.

### Step 2: Verify the JWT

1. **Verify signature** using Apple's public key matching the `kid` in the JWT header
2. **Verify `iss`** equals `https://appleid.apple.com`
3. **Verify `aud`** equals your app's bundle identifier (`com.yourcompany.WeightApp`)
4. **Verify `exp`** (expiration time) has not passed
5. **Verify `iat`** (issued at) is not in the future

### Step 3: Exchange Authorization Code (Optional)

For additional security, exchange the authorization code for tokens:

```
POST https://appleid.apple.com/auth/token
Content-Type: application/x-www-form-urlencoded

client_id=com.yourcompany.WeightApp
client_secret=<client_secret_jwt>
code=<authorization_code>
grant_type=authorization_code
```

**Note**: The client secret is a JWT you generate using your Apple Developer credentials.

## User ID Handling

### Key Points

1. **Apple User ID (`sub`)** is stable and unique per user per developer team
2. The same user will have different IDs for different developer teams
3. Store this ID in your database to identify returning Apple users
4. If a user signs in with Apple and their email matches an existing account, consider linking the accounts

### Recommended Database Schema Addition

```sql
-- Add to users table or create separate table
ALTER TABLE users ADD COLUMN apple_user_id VARCHAR(255) UNIQUE;
```

## Email Relay Considerations

When `is_private_email` is `"true"`:
- Apple provides a relay email like `abc123@privaterelay.appleid.com`
- Emails sent to this address are forwarded to the user's real email
- You must register your sending domain with Apple to use this feature
- The relay address is stable - same user will have same relay address

## Error Scenarios to Handle

| Scenario | Suggested Response |
|----------|-------------------|
| Invalid/expired identity token | 401 - "Invalid authentication token" |
| Invalid authorization code | 401 - "Invalid authorization code" |
| Token verification failed | 401 - "Authentication failed" |
| User ID already linked to another account | 409 - "Apple account already linked" |
| Server error during Apple API call | 500 - "Authentication service unavailable" |

## Implementation Checklist

- [ ] Create `/auth/apple-signin` endpoint
- [ ] Implement JWT verification using Apple's public keys
- [ ] Cache Apple's public keys (they rotate periodically)
- [ ] Store Apple user ID for returning users
- [ ] Handle email/name only on first sign-in
- [ ] Support account linking for existing email matches
- [ ] Return standard `AuthResponse` format
- [ ] Handle private email relay addresses

## Testing

### Manual Testing Flow

1. Build and run the app on a real device (Simulator has limitations)
2. Tap "Sign in with Apple" button
3. Authenticate with your Apple ID
4. Verify the request reaches your backend with correct data
5. Test subsequent sign-ins (email/name will be `null`)

### Test User Considerations

- You can sign out of Apple ID in device Settings to test as a "new user"
- Use a test Apple ID separate from your production account
- Remember that email/name are only sent on FIRST authorization

## Apple Developer Resources

- [Sign in with Apple REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api)
- [Generate and Validate Tokens](https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens)
- [Fetch Apple's Public Key](https://developer.apple.com/documentation/sign_in_with_apple/fetch_apple_s_public_key_for_verifying_token_signature)
- [Handle User Credentials](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/authenticating_users_with_sign_in_with_apple)

## iOS Client Code Reference

The iOS implementation is in:
- `WeightApp/Services/AppleSignInService.swift` - Token handling
- `WeightApp/Services/APIService.swift` - API method (currently placeholder)
- `WeightApp/ViewModels/AuthViewModel.swift` - Auth flow coordination
- `WeightApp/Views/Auth/LoginView.swift` - Login UI
- `WeightApp/Views/Auth/RegisterView.swift` - Registration UI

When the backend endpoint is ready, update `APIService.swift` to:
1. Remove the `throw APIError.notImplemented(...)` line
2. Uncomment the actual API call
3. Store tokens as done in `login()` method
