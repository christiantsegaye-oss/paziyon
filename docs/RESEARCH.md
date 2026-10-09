# PAZIYON: Research and Ideation Trail

This file records **why** PAZIYON is built the way it is: the problem, the evidence, the ideas we rejected, and how each research finding became a feature. It is the in-repo copy of our **Scholarxiv** ideation trail (STARK requirement 01). The day-by-day decisions are in [`DECISIONS.md`](DECISIONS.md).

> **Status:** draft. Every source below is real and linked. Before submitting, add each one to Scholarxiv through its Papers API and paste the Scholarxiv link next to it. Entries marked _[team to add]_ need the team's own input.

---

## 1. The problem

### 1.1 Epilepsy is common, and most people with it live where care is scarce
- About **50 million people** worldwide have epilepsy. Nearly **80%** of them live in low- and middle-income countries. [1]
- **Three in four** people with epilepsy in low-income countries do not get the treatment they need. [1]
- Up to **70%** could live seizure-free if diagnosed and treated, and medication can cost as little as **US$ 5 a year**. [1]
- People with epilepsy face up to **three times** the risk of premature death of the general population. [1]
- WHO links the treatment gap to too few health workers, poor access to medicines, **"societal ignorance and misconceptions"**, poverty and low priority. Low-income countries have a median of **0.03 neurologists per 100,000 people**. [1][2]

### 1.2 In Ethiopia, the people nearby often don't know what to do, or fear it
- A meta-analysis of 9 Ethiopian studies found **about 52%** of the public hold unfavourable attitudes towards people with epilepsy. These attitudes are linked to exclusion, physical punishment and assault. **People who had witnessed a seizure were more likely to hold them** (AOR 2.70). [3]
- Among patients already on medication in Ethiopian clinics, only **about 46%** were seizure-free (meta-analysis of 23 studies). [4] This means many people still have seizures in public even while on treatment.
- Community surveys report active epilepsy at **5.2 per 1,000** in central Ethiopia [5] and up to **29.5 per 1,000** in Zay villages, Oromia [6], so prevalence varies widely by place.
- _[team to add]_ What we saw while volunteering at **Care Epilepsy Ethiopia**: common myths (holy water, putting objects in the mouth, holding the person down), how long help took to arrive, and how families were contacted.

### 1.3 Time matters
- A tonic-clonic seizure lasting **more than 5 minutes** is status epilepticus and should be treated as an emergency. After **30 minutes**, the risk of lasting harm rises. [7]
- So bystanders need to know **how long** a seizure has lasted, and when to call an ambulance.

**Problem statement:** during and after a seizure, the person can't call for help or explain what to do, and the people nearby often don't know first aid or believe harmful myths. Data connectivity is unreliable, and most people speak Amharic or Afaan Oromo, not English.

---

## 2. From evidence to features

| Finding | What PAZIYON does |
|---|---|
| Bystanders don't know first aid, and myths are common [1][3] | Bystander mode reads **myth-free first-aid steps** aloud in Amharic, Afaan Oromo and English. Step 2 says: "Do not restrain them. Do not put anything in their mouth." |
| A seizure over 5 minutes is an emergency [7] | The emergency screen shows a **running timer**. Bystanders can ask "How long has it been?". After 5 minutes the app says to call **907**. |
| The person may not be able to tap during an aura, or after falling | Several ways to trigger help: **voice** (Voxide), **hold-to-alert**, **power button ×3** with the phone locked, and **automatic fall detection** |
| The language barrier | Voice in all three languages through **Voxide**. The app answers in the language it was asked in. |
| Data connectivity is unreliable | The alert **SMS goes directly from the phone** with GPS, so it **works offline**. A recorded-audio fallback covers having no internet. |
| Few people come over to help, or no one notices | A **loud siren** draws people over before and between instructions |
| Doctors need seizure history | **Event history** with CSV export for the clinic visit, and a **caregiver dashboard** |
| False alarms make contacts ignore alerts | A **10–30 s cancel window** with voice cancel ("ደህና ነኝ", "Nagaan jira") |

---

## 3. Routes we considered and rejected

| Idea | Why we rejected it | Evidence |
|---|---|---|
| **Detect seizures** from the phone's motion sensors | Even dedicated wearables only have a *weak* recommendation, and only for tonic-clonic seizures, with false alarms still reported. A phone in a pocket gives noisier data. We detect **falls** (freefall → impact → stillness) and let the person trigger help in other ways. | [8] |
| A **custom wearable** | It can't be built and validated in a 15-day hackathon. It's future work. | [8] |
| Alerts over the **internet only** | Connectivity is unreliable, so SMS from the phone is primary | _[team to add: local connectivity source]_ |
| **Pre-recorded audio** as the only "voice" | Playing audio is not voice *interaction* (STARK requirement 02). Bystanders need to ask questions. | STARK rules |
| **Robotic text-to-speech** for Amharic and Oromo | Testers couldn't understand it, so we moved to **Voxide**'s natural voice and keep the clips only as an offline fallback | Team testing, 2026-10-09 |
| A **contact-side app** | Contacts would have to install something. A web dashboard linked from the SMS needs nothing installed. | — |

---

## 4. Fall detection approach

Most fall detectors in the research literature compare accelerometer readings against thresholds. PAZIYON uses three stages:

1. **Freefall:** total acceleration drops well below 1 g.
2. **Impact:** a spike follows within a short window.
3. **Stillness:** little movement afterwards. We wait 500 ms after the impact before checking, so the bounce isn't counted as movement.

There are three sensitivity levels, so the user can trade missed falls against false alarms.
- _[team to add]_ A threshold-based fall-detection paper from Scholarxiv, e.g. a tri-axial accelerometer threshold study, to support the values in `fall_detector.dart`.

---

## 5. Clinical review
- _[team to add]_ Who at **Care Epilepsy Ethiopia** reviewed the first-aid script, when, and what they changed.
- _[team to add]_ Native-speaker review of the Amharic and Afaan Oromo text (`app/lib/core/content.dart`, `prototype/js/core/content.js`).

---

## References
1. World Health Organization. *Epilepsy* (fact sheet), 7 Feb 2024. https://www.who.int/news-room/fact-sheets/detail/epilepsy
2. WHO. *Global burden of epilepsy and the need for coordinated action* (A68/12), 2015. https://apps.who.int/gb/ebwha/pdf_files/WHA68/A68_12-en.pdf
3. *Unfavorable public attitude toward people with epilepsy in Ethiopia: a systematic review and meta-analysis*, 2023. https://www.frontiersin.org/journals/neurology/articles/10.3389/fneur.2023.1086622/pdf
4. *Treatment outcome of epileptic patients receiving antiepileptic drugs in Ethiopia: a systematic review and meta-analysis*. Behavioural Neurology, 2021. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8140843/
5. Tekle-Haimanot R. et al. Community-based study of epilepsy in central Ethiopia (1986–1988 survey; 5.2 per 1,000). _[team: confirm the full citation on Scholarxiv]_
6. Door-to-door epilepsy survey in Zay villages, Oromia, 2006 (29.5 per 1,000). _[team: confirm the full citation on Scholarxiv]_
7. Trinka E. et al. *A definition and classification of status epilepticus: Report of the ILAE Task Force on Classification of Status Epilepticus*. Epilepsia 2015;56(10):1515–1523. https://doi.org/10.1111/epi.13121
8. Beniczky S. et al. *Automated seizure detection using wearable devices: a clinical practice guideline of the ILAE and IFCN*. Epilepsia 2021. https://doi.org/10.1111/epi.16818
