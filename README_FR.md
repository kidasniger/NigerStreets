# Ch31 — Rond-point + routes 🛣️🎮

Le code charge automatiquement :

`res://assets/environment/rond-point-elf.glb`

Tu n'as **pas besoin de glisser le GLB dans la scène**.

## Fichiers à remplacer

Remplacer :
- `res://scenes/world.tscn`
- `res://scripts/world.gd`

Créer le dossier :
- `res://assets/environment/`

Puis placer :
- `res://assets/environment/rond-point-elf.glb`

## Ce qui est généré automatiquement

- Rond-point 3D chargé depuis le GLB.
- Quatre routes : nord, sud, est, ouest.
- Collisions des routes.
- Trottoirs simples.
- Marquages centraux.
- Collision approximative de l'îlot central.
- Sol de 100 x 100 m.
- Joueur placé au début d'une route.

Le GLB fourni a été inspecté : son emprise horizontale est d'environ 1,36 m. Le script utilise une échelle par défaut de 6 pour obtenir un rond-point d'environ 8 m de rayon/ordre de grandeur adapté au personnage. Le paramètre `roundabout_scale` peut être ajusté dans l'inspecteur sans modifier le code.

La lumière principale n'a pas d'ombres dans cette scène de prototype afin d'éviter l'effet de grande silhouette que tu avais signalé.
