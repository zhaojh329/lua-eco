# Code Review Template

## Output Order
1. Findings ordered from highest to lowest severity
2. Key risks and behavioral regression points
3. Test gaps
4. Secondary improvement suggestions

## Finding Template
- Severity: Critical | High | Medium | Low
- Location: file and symbol
- Symptom: current behavior
- Risk: failure path or blast radius
- Fix: smallest viable fix
- Test recommendation: tests to add or update

## Required Review Dimensions
- Whether API selection matches the task capability.
- Whether object fields, return tuples, and handler signatures match documented lua-eco shapes.
- Whether blocking interfaces are misused.
- Whether nil, err return values are fully handled.
- Whether timeouts are explicit and reasonable.
- Whether resources are reliably released.
- Whether concurrent paths have races.
- Whether platform dependencies are declared and degraded gracefully.

## Routing Guard Review Dimensions
- Whether nonexistent function names are called.
- Whether invented field names or response shapes are used.
- Whether APIs are reused across mismatched capabilities.
- Whether a merely similar interface is treated as an equivalent substitute.
- If any of these problems exist, require a fallback rewrite plan.
