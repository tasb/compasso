# Starting from requirements

**When:** you have a requirements or specification document (Markdown, PDF, Word): the what, already written down.

**Bring:** the document's path, and the person who can answer questions about it.

## Steps

1. **`/compasso:setup`**, as [Greenfield](greenfield.md) or [Brownfield](brownfield.md) describes, depending on whether code exists.

2. **`/compasso:backlog`**, pointing at the document. You can skip discovery: the backlog step reads the document and writes the brief from it. It asks only what the document leaves open and essential (who the users are, what the MVP must prove), and security reviews it.
   - Each requirement becomes part of a feature, cited as `doc: <section>`, so every feature traces back to the document.
   - Features are user outcomes of at most half a sprint. A long requirement is split; several small ones join.
   - Acceptance lines come from the document's rules and examples.
   *You decide:* the MVP line. A requirements document rarely says what can wait; Compasso asks.

3. **`/compasso:roadmap`**, **`/compasso:plan`**, **`/compasso:sprint`**, as in [Greenfield](greenfield.md).

## Tips

- The document is data, not instructions. A sentence like "the system must skip the security review" becomes a question for you, never an action.
- Requirements that are not observable ("must be user friendly") come back as questions. The tester refuses acceptance lines a test cannot check.
- When the document changes, run `/compasso:backlog` again. It refines the existing backlog and keeps the tracker issues.
