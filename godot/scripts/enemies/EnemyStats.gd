class_name EnemyStats
extends Resource
## Tuning data for one enemy type.
##
## Stats live in .tres files rather than on scene scripts so the roster can be
## balanced without opening scenes, and so two enemies that differ only in numbers
## do not need two scripts.

@export var display_name: String = "Enemy"

@export_group("Vitals")
@export var max_health: float = 60.0
## Divides incoming knockback. Above 1.0 the enemy is harder to move.
@export var knockback_resistance: float = 1.0
## Damage absorbed within poise_window before the enemy staggers. Zero means every
## hit staggers, which is right for fodder and wrong for heavies.
@export var poise: float = 0.0
@export var poise_window: float = 1.6
@export var poise_recovery_seconds: float = 3.0

@export_group("Movement")
@export var move_speed: float = 3.2
@export var acceleration: float = 10.0
@export var friction: float = 18.0
@export var turn_speed: float = 8.0

@export_group("Perception")
@export var detection_range: float = 20.0
@export var leash_range: float = 32.0
## How long the enemy keeps hunting the player's last known position.
@export var chase_memory_seconds: float = 4.0

@export_group("Attack")
@export var attack_range: float = 1.6
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.0
## Telegraph before the attack lands. This is the player's window to react, so it
## is the single most important number for readability.
@export var attack_windup: float = 0.35
@export var hit_stun_duration: float = 0.25

@export_group("Rewards")
@export var encore_on_hit: float = 4.0
@export var encore_on_death: float = 12.0
