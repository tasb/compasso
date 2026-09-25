# Starting from a prototype

**When:** someone built a clickable prototype that shows the screens and flows the product needs, such as a Lovable, v0 or Bolt app, a hand-built front end, or a Figma file, and you want to build the real product from it.

**Bring:** one of:
- the URL of the running prototype (public, no login yet);
- the path to its source code;
- the Figma file, through the Figma connector or as frames you export to a folder.

**Remember:** the prototype is a **reference**, not the codebase. The product is rebuilt test-first. The prototype tells you *what* to build: screens, fields, flows, wording.

## Steps

1. **`/compasso:setup`** in the product's repository. It is usually a new repository, so read [Greenfield](greenfield.md) step 1.

2. **`/compasso:discover`**, and say you have a prototype.
   - **Running app:** Compasso crawls it in a browser (Docker). It visits every page it can reach through links on the same site, saves a screenshot and the headings, forms, fields and buttons of each, and stops at 40 pages. It **only follows links**: it never clicks buttons, never submits forms, and skips links that look like logout or delete.
   - **Source code:** the planner reads the routes, pages and forms.
   - **Figma:** the planner reads the frames.
   All three produce the same **screen inventory**, `.compasso/product/prototype.json`: one entry per screen, the forms and actions on it, which screens it links to, and the flows (sign-up, checkout).
   Then come the questions a crawl cannot answer. *You decide:*
   - what happens after each form is sent;
   - which screens sit behind a role;
   - which parts of the prototype are fake (mock data, no backend);
   - who the users are, and what the MVP must prove.
   *You get:* the brief, the inventory, and a merge request.

3. **`/compasso:backlog`.** Features are built from the screens and flows.
   - Each feature lists the screens it covers (`screen: checkout`).
   - Every screen must belong to a feature, or be left out on purpose. `backlog-check` points out any screen nobody covers, and the decision record says why one was left out.
   - Forms become acceptance lines: required fields, what happens on success and on a mistake.
   - Flows show the dependencies: checkout depends on the cart.
   *You decide:* the stack for the walking skeleton, and the MVP line.

4. **`/compasso:roadmap`**, then **`/compasso:plan`** and **`/compasso:sprint`**, as in [Greenfield](greenfield.md).

5. **UI stories point at the screen** they rebuild, so the builder matches its fields and wording, and the e2e tests follow its flow.

## Tips

- A prototype hides its backend. Expect the questions in step 2 to reveal work the screens don't show: accounts, emails, payments, admin screens.
- If the prototype needs a login, it can't be crawled yet. Export the Figma frames or point at the source code instead.
- Crawl a stable URL. Re-crawling later gives a new inventory to compare against, if the prototype keeps changing.
