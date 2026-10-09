PAZIYON
PAZIYON (Pre-seizure Aura Zonal Intervention 
Yielding Optimal Networks) is a voicenfirst 
mobile emergency app for people living with 
epilepsy. It alerts emergency contacts, guides 
bystanders through first aid in their own 
language, and keeps a history of events for 
doctors. It is built for seizures that cause falls: 
clonic, tonic-clonic and atonic.
The Inspiration & Vision
The idea for PAZIYON came from our team's 
shared volunteering experience at Care Epilepsy
Ethiopia. We saw how vulnerable people living 
with epilepsy are, so we focused the project on 
the pre-seizure aura window and on long-term 
clinical care.
When a seizure aura begins, fine motor skills 
quickly get worse and speech is often lost 
(transient ictal aphasia), so a normal phone 
screen becomes hard to use. PAZIYON adds 
several layers of protection:
it protects the user during an episode;
it guides people nearby through myth-free 
first aid;
it logs each event for the user's doctor.
Core Features
Many ways to trigger help:
Voice: handsnfree voice commands 
through Voxide, in Amharic, Afaan Oromo 
and English ("እርዳታ", "Na gargaari", 
"Help").
Hold to alert button.
Phone locked or screen off: three presses
of the power button, or the "Get help now" 
button on the lock screen.
Automatic fall detection: the 
accelerometer looks for freefall, then 
impact, then stillness, with Low, Medium or
High sensitivity.
Cancel window: a 10–30 second countdown 
before anything is sent. The user can cancel 
it by voice ("ደህና ነኝ", "Nagaan jira", "I'm 
okay") or by tapping.
Emergency alert:
The phone sends an SMS with the user's 
GPS location to their emergency contacts. 
It goes directly from the phone, so it 
works offline.
When the user recovers, an "I'm okay" 
SMS follows.
Public beacon for bystanders:
A loud siren draws people over, even 
when the phone is on silent.
The screen switches to a high-visibility 
emergency view showing the medical ID 
and a "Call 907" button.
Voxide reads the first-aid steps aloud in 
Amharic, Afaan Oromo and English.
Bystanders can talk to the phone: "How 
long has it been?", "What do I do now?", 
"Call for help".
Works with the app closed: a background 
service keeps fall detection running. If 
nobody is at the phone, the service runs the 
whole alert itself.
For caregivers and doctors:
a caregiver dashboard (web) shows the 
live alert, a map and the medical ID;
the event history (time, trigger, duration, 
outcome) exports as CSV for the user's 
doctor.
Technical Architecture
Mobile app & core logic: Flutter & Dart 
(Android)
Voice: Voxide (voice recognition and natural 
speech in Amharic, Afaan Oromo and 
English), with the phone's recognizer and 
recorded audio as an offline fallback
Alerts: direct SMS from the phone, so no 
data connection is needed
Storage: on the device only. Medical data is 
shared only during an active alert.
Web demo & caregiver dashboard: HTML/
JavaScript
Project Team
Christian Tsegaye: Project lead. Owns the 
main repository  
of the web demo and caregiver dashboard; 
coordinates the team and releases.
Eyueal Tibebu: UI and branding lead. Built 
the app and web screens: Voxide settings, 
the siren switch, the "Silence siren" button 
on the emergency screen and the PAZIYON 
branding. Also wrote the app and web-demo 
READMEs.
Hasset Jenberu: Localization and voice lead. 
Integrated Voxide for Amharic, Afaan Oromo 
and English: the voice engine, the bridge that 
runs Voxide inside the Android app, the 
microphone and network permissions, and 
the Voxide setup guide. Also reviews the 
first-aid text in all three languages.
Rakeb Fikiru: Sensor and core logic lead. 
Owns the alert flow (countdown, fall 
detection, background protection), the 
emergency siren and how voice drives the 
alert. Also owns the automated tests and the 
CI build.
Lidet Kinfe: Dashboard and research lead. 
Owns the caregiver dashboard and the web 
server that hosts it on EthioDeploy, the 
decisions log and changelog, and the 
Scholarxiv research trail.
