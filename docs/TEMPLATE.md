# bashframes app landing pages

Every bashframes app landing page must include an All apps link in the top nav and in the footer. Both go to https://bashfra.me/apps/, not a github.io URL.

The narrow header hides ordinary nav links. The nav item uses `class="apps"` so it stays on screen under 480px, the same way the guide link does.

## Top nav

```html
<a class="apps" href="https://bashfra.me/apps/">All apps</a>
```

Put that in the primary nav, before the download button. On a narrow screen, keep All apps visible and keep the labels on one line:

```css
.nav-links { flex-wrap: nowrap; gap: var(--space-2) var(--space-3); }
.nav-links a { white-space: nowrap; }
.nav-links .download { padding-inline: var(--space-3); }
.nav-links a:not(.download):not(.guide):not(.apps) { display: none; }
```

## Footer

```html
<a href="https://bashfra.me/apps/">All apps</a>
```

Put that in the footer nav with the other links. It has no extra class and uses the existing footer link style.
