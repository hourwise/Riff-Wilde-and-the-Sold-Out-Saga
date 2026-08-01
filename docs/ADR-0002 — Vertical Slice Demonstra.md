ADR-0002 — Vertical Slice Demonstration
Status

Accepted

Context

The long-term vision for Riff Wilde and the Sold-Out Saga is a single-player third-person fantasy action adventure built in Godot 4 with stylised low-poly visuals, music-driven combat and RPG progression.

The complete game is expected to contain multiple hub towns, several exploration zones per act, evolving musical progression, spectral companion mechanics and cinematic storytelling.

Attempting to build the entire game immediately would introduce excessive scope and delay validation of the core gameplay.

Instead, development shall focus on a polished vertical slice representing approximately 10–15 minutes of finished gameplay.

This slice should demonstrate the game's core identity rather than act as an introductory tutorial.

Decision

The playable demo will represent a mid-game mission.

The player begins having already defeated the first major boss.

The first legendary instrument has already been recovered.

The first spectral musician (Sir Brass) is available.

No lengthy exposition is provided.

Players are immediately introduced to the established world and core mechanics.

Objectives

The vertical slice must answer one question:

"If the entire game reached this quality, would players want more?"

Gameplay Flow
Opening Cinematic

↓

Inn Hub

↓

Accept Mission

↓

Travel to Cemetery

↓

Explore Zone

↓

Fight Enemy Groups

↓

Clear Cemetery

↓

Summon Mini Boss

↓

Mini Boss Fight

↓

Return To Tavern

↓

Encore Performance

↓

End Demo
Hub

The hub shall be intentionally small.

Required NPCs:

Tavern Keeper
Merchant
Blacksmith
Quest Giver

Sir Brass should wander naturally and occasionally interact with Riff.

The hub primarily exists to establish the game's personality rather than provide extensive RPG systems.

Demo Level

Environment:

Old church cemetery.

Visual themes:

heavy fog
moonlight
gothic ruins
crypts
mausoleums
broken angel statues
dead trees
flickering torches

Approximate completion time:

10–15 minutes.

Exploration

The cemetery shall consist of several interconnected regions.

Recommended structure:

Entrance
Crypts
Graveyard
Mausoleum
Church Courtyard

Multiple routes should exist.

Players may explore in different orders.

Shortcuts and loops are encouraged.

Dead ends should reward exploration with lore or collectibles.

Navigation

The player receives:

Compass
Mini-map
Fog of war

Fog clears through exploration and defeating enemy groups.

The Church remains visible throughout the level as the primary landmark.

Progression Gate

The Mini Boss does not appear immediately.

Instead:

Each major cemetery section contains one corrupted Funeral Altar.

Clearing enemies allows the altar to be cleansed.

Once every altar has been restored:

church bell rings
choir echoes
Sir Brass comments
Mini Boss appears

This creates a narrative trigger instead of an invisible completion percentage.

Enemy Types

The demo shall intentionally limit enemy variety.

Required enemies:

Tone Deaf

Basic zombie.

Used for combo learning.

Grave Crawlers

Fast melee attackers.

Encourage crowd control.

Hollow Choir

Support enemies.

Buff nearby undead through corrupted singing.

Must be interrupted.

Bone Bell Ringer

Heavy enemy.

Uses slow shockwave attacks.

Introduces stagger mechanics.

Companion System

Only one companion is available.

Sir Brass.

Companions are not permanent AI followers.

Instead:

Player builds Encore.

Player activates Sir Brass.

Sir Brass materialises.

Performs one signature attack.

Returns to spectral form.

This reduces AI complexity while maintaining spectacle.

Mini Boss

The Choirmaster.

An undead cathedral conductor.

Mechanics:

summons undead choir
rhythm-based attacks
musical counterplay
corrupted singing

Sir Brass assists during specific phases.

Music System

Music evolves dynamically.

Exploration:

ambience only

Combat:

guitar

Higher combo:

percussion

Higher combo:

trumpet

Maximum Encore:

Full combat arrangement.

Music is gameplay feedback.

Cinematics

Required:

Opening

Mini Boss introduction

Mini Boss defeat

Return to Tavern

Encore performance

Tavern Encore

Every completed level returns to the Inn.

The same core song is performed.

Each completed region adds:

new verse
additional instrument
richer harmony
stronger crowd reaction

The player's progress should be audible.

Success Criteria

The demo succeeds if players understand:

who Riff is
why music matters
how combat works
how companions work
why they want to collect more instruments
why they want to hear the next Tavern performance
Consequences

The vertical slice becomes the benchmark for:

art direction
animation quality
combat feel
music
cinematics
dialogue
companion mechanics
level design

Future acts expand this foundation rather than replace it.