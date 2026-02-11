# Suggested User Properties API Changes

## New Field

Add `selectedExerciseId` to the UserProperties model:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `selectedExerciseId` | UUID string | No | null | ID of the user's currently selected exercise |

## Updated Response

```json
{
  "bodyweight": 180.0,
  "availableChangePlates": [2.5, 5.0, 10.0],
  "minReps": 5,
  "maxReps": 10,
  "selectedExerciseId": "550e8400-e29b-41d4-a716-446655440000"
}
```

## Notes

- If the referenced exercise is deleted, return null
- Field is optional on both GET and PUT
