// Generates the Amharic and Afaan Oromo voice clips the app and web demo play
// during an alert. Phones and browsers have no voice for these languages, so
// without clips the instructions would be silent.
//
// Uses espeak-ng (offline, robotic but intelligible). Replace any clip with a
// human recording of the same text and file name; that is the plan for the
// final, CEE-reviewed audio.
//
//   apt-get install espeak-ng lame
//   node tools/generate_audio.mjs
//
// Text comes from prototype/js/core/content.js, the same source the screens use.

import { execFileSync } from 'node:child_process';
import { mkdirSync, copyFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FIRST_AID_STEPS, COUNTDOWN_PROMPT, ANSWERS, ELAPSED_SPOKEN } from '../prototype/js/core/content.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDirs = [join(root, 'app/assets/audio'), join(root, 'prototype/audio')];
const LANGS = ['am', 'om'];

function clips(lang) {
  const list = [];
  FIRST_AID_STEPS[lang].forEach((text, i) => list.push([`step-${i + 1}`, text]));
  for (let n = 5; n <= 30; n++) list.push([`countdown-${n}`, COUNTDOWN_PROMPT[lang](n)]);
  for (let m = 0; m <= 30; m++) list.push([`elapsed-${m}`, ELAPSED_SPOKEN[lang](m)]);
  for (const key of ['overFiveMinutes', 'calling', 'holdToStop', 'notUnderstood']) list.push([`answer-${key}`, ANSWERS[key][lang]]);
  return list;
}

const tmp = join(root, '.audio-tmp.wav');
const manifest = {};
for (const lang of LANGS) {
  manifest[lang] = {};
  for (const dir of outDirs) {
    rmSync(join(dir, lang), { recursive: true, force: true });
    mkdirSync(join(dir, lang), { recursive: true });
  }
  for (const [name, text] of clips(lang)) {
    execFileSync('espeak-ng', ['-v', lang, '-s', '135', '-a', '200', '-w', tmp, text]);
    const mp3 = join(outDirs[0], lang, `${name}.mp3`);
    execFileSync('lame', ['--quiet', '-m', 'm', '-b', '48', tmp, mp3]);
    copyFileSync(mp3, join(outDirs[1], lang, `${name}.mp3`));
    manifest[lang][name] = text;
  }
}
rmSync(tmp, { force: true });
for (const dir of outDirs) writeFileSync(join(dir, 'clips.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Generated ${Object.values(manifest).reduce((n, m) => n + Object.keys(m).length, 0)} clips into ${outDirs.join(', ')}`);
