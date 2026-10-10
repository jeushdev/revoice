# ReVoice demo script (about 1 minute)

## Before going on stage

1. Install the Release build with bundled models (README, "iPhone (real models)"). `Target.xcconfig` must be `lib/main.dart`.
2. Turn Wi-Fi and mobile data off (airplane mode). Low Power Mode off. Settings: **Sample data** off.
3. Do one full dry run so the models are warm. Force quit the app, reopen it, and check it starts.
4. Have a second person ready (Mark and Anna below), or use Sample data as the fallback.

## Script (two people, face to face)

Tap the mic. In the names sheet type `Mark, Anna` and start.

Speak naturally, with a short pause between turns:

1. Mark: "Hi Anna, thanks for meeting me."
2. Anna: "Thanks Mark. We have a problem with lost orders. Our staff write them on paper and some get lost."
3. Mark: "I see. Our app keeps every order in one place."
4. Anna: "How much does it cost?"
5. Mark: "It costs 500 pesos a month."
6. Anna: "That works for us. Let's go with the monthly plan."
7. Mark: "Great. I'll send the setup guide by Friday."
8. Anna: "I'll train my staff on Monday."

What to show:

- Live captions with Mark and Anna labels. If both voices get one label, tap **Switch speaker** at each turn, then **Auto**.
- Tap Stop. "Summarizing on this phone" appears, then the summary.
- Open the suggested questions. They are already answered, so each tap shows the answer at once, with sources.
- Type a question: "Did they talk about delivery?" Expected: "Not mentioned in this conversation."
- Open the Transcript tab: Clean (merged turns) and Original.
- Say it out loud: airplane mode is on, nothing left the phone.

## Expected answers

| Question | Expected |
| --- | --- |
| What problem does Anna have? | lost orders |
| How much does it cost? | 500 pesos a month |
| What will Mark do and when? | send the setup guide by Friday (the model may also wrongly credit Monday to Mark) |
| Did they talk about delivery? | Not mentioned |

## If something goes wrong

- No speech or one label for everyone: use Switch speaker, or turn **Sample data** on and play the scripted meeting.
- Summary fails or is slow: tap Retry. If the error mentions decoding, force quit and reopen, then re-run.
- Wrong attribution in the summary: rename or fix a line's speaker, wait 2 seconds, and the summary rewrites itself.
- Do not rely on action items or "who agreed to what" being right; keep the story on captions, summary and Ask.

## Things not to claim

- No measured numbers for this phone unless SUBMISSION.md has them filled in.
- No CRM. No other languages. No saved Library after the app is closed.
