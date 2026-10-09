# First-aid audio recordings

Drop the Care Epilepsy Ethiopia–reviewed recordings here and the bystander screen plays them instead of text-to-speech:

```
audio/am/step-1.mp3 … step-7.mp3   Amharic
audio/om/step-1.mp3 … step-7.mp3   Afaan Oromo
audio/en/step-1.mp3 … step-7.mp3   English
```

Step numbers follow the script in `docs/SPEC.md` section 4.3 (and `js/core/content.js`). When a file is missing, the app falls back to the browser's voice for that language, or shows the text only if the browser has no voice for it.
