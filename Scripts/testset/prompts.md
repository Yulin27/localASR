# Recording prompts for Phase 0 gaps

The Typeless history covers Chinese, English, and natural Chinese/English
code-switching. It contains no French and no controlled edge cases. Record the
material below to complete the Phase 0 input set.

Read each prompt aloud at normal dictation pace. Do not over-articulate — the
gate is about realistic dictation, not clean speech.

## Recording

Capture 16 kHz mono directly, matching the app's capture format:

```
ffmpeg -f avfoundation -i ":default" -ac 1 -ar 16000 -sample_fmt s16 \
  TestData/recorded/fr-01.wav
```

List devices with `ffmpeg -f avfoundation -list_devices true -i ""`. Stop with
`q`. The first run prompts for microphone access.

Name files `<lang>-<nn>.wav` using `fr`, `en`, `zh`, `mix`, or `edge`. Keep a
plain-text file beside each recording with the exact words spoken — unlike the
Typeless history, these are verified references and are worth writing down.

## French — the missing language

1. Je voudrais qu'on décale la réunion de demain à quatorze heures trente.
2. Peux-tu m'envoyer le devis avant vendredi, s'il te plaît ?
3. Le problème vient de la configuration réseau, pas du code lui-même.
4. J'ai relu le contrat : la clause de résiliation demande un préavis de trois mois.
5. Franchement, je pense qu'on devrait commencer par la version la plus simple,
   quitte à la retravailler plus tard.

## French with technical English terms

6. Il faut déployer le worker sur LiveKit avant de lancer les tests.
7. On utilise un modèle Qwen 3 quantisé en quatre bits, ça tourne en local.

## Short utterances

8. (fr) D'accord.
9. (en) Sounds good to me.
10. (zh) 好的，明白了。

## Numbers, dates, and units — inverse text normalization

11. (fr) Le rendez-vous est le douze mars deux mille vingt-six à neuf heures moins le quart.
12. (en) The build dropped from four point two seconds to about eight hundred milliseconds.
13. (zh) 这个模型大概占三点五个 G 的内存，加载要十二秒左右。

## Self-correction and fillers

14. (en) So the plan is — actually, wait, let me start over. The plan is to ship
    the mock slice first, then swap in the real model.
15. (fr) On peut, euh, on peut faire ça la semaine prochaine je pense.

## Long-form dictation

16. Speak for at least ninety seconds in French about anything real — a project
    update, a summary of your week. Long input is where memory pressure and
    thermal behavior show up, and the history has no long French clip.

## Edge cases

17. `edge-silence.wav` — start recording, say nothing for ten seconds, stop.
18. `edge-noise.wav` — ten seconds of room noise with no speech.
19. `edge-truncated.wav` — begin a sentence and stop recording mid-word.

The history already supplies 23 natural no-speech presses, so 17 through 19 are
controlled duplicates rather than the only coverage. Record them anyway; knowing
the exact input matters when a model returns hallucinated text on silence.
