# WeightApp iOS - Data Schema

## SwiftData Models

### Exercises

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| id | UUID | auto-generated | `@Attribute(.unique)` |
| name | String | - | Exercise name |
| isCustom | Bool | - | Custom vs predefined |
| loadType | String | "Barbell" | Raw value of `ExerciseLoadType` enum |
| createdAt | Date | `Date()` | Creation timestamp |
| createdTimezone | String | `TimeZone.current.identifier` | |
| notes | String? | nil | Optional user notes |
| deleted | Bool | false | Soft delete flag |
| icon | String | "figure.stand" | SF Symbol or custom icon |

**Enum: ExerciseLoadType**
- `barbell` = "Barbell"
- `singleLoad` = "Single Load"

---

### LiftSet

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| id | UUID | auto-generated | `@Attribute(.unique)` |
| exercise | Exercises? | - | `@Relationship` to Exercises |
| reps | Int | - | Number of repetitions |
| weight | Double | - | Weight used |
| createdAt | Date | `Date()` | Creation timestamp |
| createdTimezone | String | `TimeZone.current.identifier` | |
| deleted | Bool | false | Soft delete flag |

---

### Estimated1RM

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| id | UUID | auto-generated | `@Attribute(.unique)` |
| exercise | Exercises? | - | Relationship to Exercises |
| value | Double | - | Estimated one-rep max |
| setId | UUID | - | Links to the LiftSet that produced this estimate |
| createdAt | Date | `Date()` | Creation timestamp |
| createdTimezone | String | `TimeZone.current.identifier` | |
| deleted | Bool | false | Soft delete flag |

---

### UserProperties (Singleton)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| id | UUID | `00000000-...0001` | Fixed singleton ID |
| bodyweight | Double? | nil | Optional |
| availableChangePlates | [Double] | [] | Weight plate denominations |
| progressMinReps | Int | 4 | Maps to `minReps` |
| progressMaxReps | Int | 8 | Maps to `maxReps` |
| activeSetPlanId | UUID? | nil | |
| stepsGoal / proteinGoal | Int? | nil | |
| bodyweightTarget | Double? | nil | |
| timezoneIdentifier | String? | nil | Mirror of pushed `timezone` (push-only, change-detection) |
| localeIdentifier | String? | nil | Mirror of pushed `locale` (push-only, change-detection) |
| languageCode | String? | nil | Mirror of pushed `language` (push-only, change-detection) |
| biologicalSex | String? | nil | "male" / "female" |
| weightUnit | String | "lbs" | "lbs" / "kg" |
| hasMetStrengthTierConditions | Bool | false | |

`hasCompletedOnboarding` is push-only and has **no** local model field — it is driven by the
UserDefaults flag `onboardingCompletePendingSync` and pushed via `SyncService.syncOnboardingCompleteIfNeeded()`.

---

### PremiumEntitlement (Singleton)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| id | UUID | `00000000-...0002` | Fixed singleton ID |
| isPremium | Bool | false | |
| subscriptionType | String? | nil | "monthly" or "yearly" |
| expiresAt | Date? | nil | nil = manually enabled (dev) |
| transactionId | String? | nil | Apple transaction ID |

**Computed:** `isActive` = isPremium AND (no expiry OR expiry in future)

---

## API Data Transfer Objects

### ExerciseDTO

| Field | Type | Notes |
|-------|------|-------|
| exerciseItemId | UUID | Maps to `Exercises.id` |
| name | String | |
| isCustom | Bool | |
| loadType | String | |
| createdTimezone | String | |
| notes | String? | |
| createdDatetime | Date? | Maps to `Exercises.createdAt` |
| deleted | Bool? | |
| icon | String? | |

### LiftSetDTO

| Field | Type | Notes |
|-------|------|-------|
| liftSetId | UUID | Maps to `LiftSet.id` |
| exerciseId | UUID | Maps to `LiftSet.exercise?.id` |
| reps | Int | |
| weight | Double | |
| createdTimezone | String | |
| createdDatetime | Date | Maps to `LiftSet.createdAt` |
| lastModifiedDatetime | Date? | |

### Estimated1RMDTO

| Field | Type | Notes |
|-------|------|-------|
| estimated1RMId | UUID | Maps to `Estimated1RM.id` |
| liftSetId | UUID | Maps to `Estimated1RM.setId` |
| exerciseId | UUID | Maps to `Estimated1RM.exercise?.id` |
| value | Double | |
| createdTimezone | String | |
| createdDatetime | Date | Maps to `Estimated1RM.createdAt` |
| lastModifiedDatetime | Date? | |

### UserPropertiesRequest

Partial-update DTO with a custom `encode(to:)` implementing key-presence semantics: a field is emitted
only when set; `clearX` flags emit an explicit `null` (field removal). All fields optional.

| Field | Type | Notes |
|-------|------|-------|
| bodyweight | Double? | + `clearBodyweight` |
| availableChangePlates | [Double]? | |
| minReps / maxReps | Int? | |
| biologicalSex | String? | + `clearBiologicalSex` |
| weightUnit | String? | |
| activeSetPlanId | String? | + `clearActiveSetPlan` |
| stepsGoal / proteinGoal | Int? | + `clearStepsGoal` / `clearProteinGoal` |
| bodyweightTarget | Double? | + `clearBodyweightTarget` |
| timezone | String? | Push-only device metadata |
| locale | String? | Push-only device metadata (e.g. "en_US") |
| language | String? | Push-only device metadata (e.g. "en") |
| hasCompletedOnboarding | Bool? | Push-only; sent `true` on onboarding completion |
| hasMetStrengthTierConditions | Bool? | |

### UserPropertiesResponse

| Field | Type |
|-------|------|
| userId | String |
| bodyweight | Double? |
| availableChangePlates | [Double]? |
| createdDatetime | String |
| lastModifiedDatetime | String |
