# Exercise Icon Field

## Overview
Exercises now have an associated icon stored as a string identifier.

## API Changes

### POST /exercises (Create/Upsert)
Request body now includes:
- `icon` (string, optional): SF Symbol name or custom asset name
- Default: "figure.stand" if not provided

### GET /exercises
Response now includes:
- `icon` (string): The icon identifier for each exercise

## Field Details
- **Type**: String
- **Max Length**: 100 characters
- **Default**: "figure.stand"
- **Examples**: "figure.squat", "BenchPressIcon", "figure.stand"

## Valid Icon Values

### SF Symbols
- `figure.stand` (default - generic standing figure)

### Custom Assets
- `OverheadPressIcon`
- `BenchPressIcon`
- `PullUpIcon`

## Migration
Existing exercises should default to "figure.stand" or be migrated
based on name-matching logic server-side:

```python
def suggest_icon(name: str) -> str:
    lowered = name.lower()

    if "overhead" in lowered and "press" in lowered:
        return "OverheadPressIcon"
    elif "bench" in lowered:
        return "BenchPressIcon"
    elif "pull" in lowered and "up" in lowered:
        return "PullUpIcon"

    return "figure.stand"
```
