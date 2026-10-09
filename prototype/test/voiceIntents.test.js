import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matchIntent, INTENTS } from '../js/core/voiceIntents.js';
import { STATES } from '../js/core/alertStateMachine.js';

test('wake phrases trigger in all three languages when idle', () => {
  assert.deepEqual(matchIntent('Help me!', STATES.IDLE), { intent: INTENTS.TRIGGER, lang: 'en' });
  assert.deepEqual(matchIntent('እርዳታ', STATES.IDLE), { intent: INTENTS.TRIGGER, lang: 'am' });
  assert.deepEqual(matchIntent('Na gargaari', STATES.IDLE), { intent: INTENTS.TRIGGER, lang: 'om' });
});

test('cancel phrases only work during the countdown', () => {
  assert.equal(matchIntent("I'm okay", STATES.COUNTDOWN).intent, INTENTS.CANCEL);
  assert.equal(matchIntent('ደህና ነኝ።', STATES.COUNTDOWN).intent, INTENTS.CANCEL);
  assert.equal(matchIntent('Nagaan jira', STATES.COUNTDOWN).intent, INTENTS.CANCEL);
  assert.equal(matchIntent("I'm okay", STATES.IDLE), null);
});

test('bystander questions route during an active alert', () => {
  assert.equal(matchIntent('How long has it been?', STATES.ACTIVE).intent, INTENTS.ELAPSED);
  assert.equal(matchIntent('What do I do now?', STATES.ACTIVE).intent, INTENTS.WHAT_TO_DO);
  assert.equal(matchIntent('Call for help', STATES.ACTIVE).intent, INTENTS.CALL_HELP);
  assert.equal(matchIntent("What's next", STATES.ACTIVE).intent, INTENTS.NEXT_STEP);
  assert.equal(matchIntent('Is she on any medication?', STATES.ACTIVE).intent, INTENTS.MEDICAL_INFO);
});

test('answers can be given in the language the bystander used', () => {
  assert.equal(matchIntent('ምን ያህል ጊዜ ሆነ?', STATES.ACTIVE).lang, 'am');
  assert.equal(matchIntent('Maal gochuu qaba?', STATES.ACTIVE).lang, 'om');
});

test('unrelated speech matches nothing', () => {
  assert.equal(matchIntent('the weather is nice', STATES.IDLE), null);
  assert.equal(matchIntent('the weather is nice', STATES.ACTIVE), null);
  assert.equal(matchIntent('', STATES.ACTIVE), null);
});

import { isEcho } from '../js/core/voiceIntents.js';
import { COUNTDOWN_PROMPT, FIRST_AID_STEPS } from '../js/core/content.js';

test('the app hearing its own prompts is treated as echo', () => {
  const spoken = [COUNTDOWN_PROMPT.en(15), FIRST_AID_STEPS.en[5]];
  assert.equal(isEcho('tap cancel if you are okay', spoken), true);
  assert.equal(isEcho('call emergency services', spoken), true);
});

test('a real speaker is not mistaken for echo', () => {
  const spoken = [COUNTDOWN_PROMPT.en(15), ...FIRST_AID_STEPS.en];
  assert.equal(isEcho("I'm okay", spoken), false);
  assert.equal(isEcho('How long has it been?', spoken), false);
  assert.equal(isEcho('What do I do now?', spoken), false);
  assert.equal(isEcho('Call for help', spoken), false);
});

test('a single "help", or help inside a sentence, triggers', () => {
  assert.equal(matchIntent('Help', STATES.IDLE).intent, INTENTS.TRIGGER);
  assert.equal(matchIntent('please help me now', STATES.IDLE).intent, INTENTS.TRIGGER);
  assert.equal(matchIntent('ድረሱልኝ', STATES.IDLE).lang, 'am');
});

test('words that merely contain a phrase do not match', () => {
  assert.equal(matchIntent('that was helpful', STATES.IDLE), null);
  assert.equal(matchIntent('unstoppable', STATES.COUNTDOWN), null);
});

test('more natural ways to cancel', () => {
  for (const phrase of ["I'm OK", 'stop', 'False alarm', 'አቁም', 'Dhaabi']) {
    assert.equal(matchIntent(phrase, STATES.COUNTDOWN)?.intent, INTENTS.CANCEL, phrase);
  }
});
