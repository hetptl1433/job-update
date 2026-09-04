# Orbit — Interactive Preview

A responsive, interactive product preview for Orbit: a personal command center that brings tasks, job search, inbox, calendar, money, health, and an assistant into one daily flow.

## What is included

- Six navigable app surfaces: Home, Tasks, Jobs, Finance, Health, and More
- Interactive task completion, job filters, detail sheets, and assistant prompts
- Working demo flows for adding a task or job opportunity
- Responsive phone-first layout with a desktop product story
- Keyboard navigation, focus management, reduced-motion support, and accessible dialogs
- Sample data labels throughout the preview

The public website is a product demo. It does not request microphone access, connect accounts, or send the visible sample data to a server. Small demo changes are saved only in the visitor's browser.

## Local development

```sh
npm run build
python3 -m http.server 4173 --directory dist
```

Then open `http://127.0.0.1:4173`.

## Deployment

Vercel runs `npm run build` and serves only `dist/`. This keeps the website release limited to `index.html`, `orbit-concept.css`, and `orbit-concept.js` instead of exposing unrelated repository files.

The legacy serverless routes under `api/` are separate from the Orbit preview and are not called by the website.
