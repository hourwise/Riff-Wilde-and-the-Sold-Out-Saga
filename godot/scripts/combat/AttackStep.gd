class_name AttackStep
extends Resource
## One swing in a melee chain.
##
## Attacks are described as data so timing can be tuned without touching control
## flow. Each step runs windup -> active -> recovery; the hitbox is live only
## during "active", and the next input is accepted once "buffer_open" has elapsed
## from the start of the step.

@export var display_name: String = "Strike"

@export_group("Damage")
@export var damage: float = 18.0
@export var knockback_force: float = 5.0
@export var resonance_gain: float = 8.0
@export var status_effect: StringName = &""
@export var status_duration: float = 0.0

@export_group("Timing (seconds)")
## Wind-up before the hitbox goes live. Long enough to read, short enough to feel
## responsive.
@export var windup: float = 0.10
## How long the hitbox stays live.
@export var active: float = 0.14
## Recovery after the hitbox closes. Cancellable by dodging.
@export var recovery: float = 0.22
## Time from the start of the step after which the next attack input is buffered.
## Buffering early is what makes a chain feel responsive rather than mashy.
@export var buffer_open: float = 0.08

@export_group("Motion")
## Weapon arc, in degrees, swept across the active window.
@export var swing_from_degrees: float = 35.0
@export var swing_to_degrees: float = -95.0
## Forward lunge applied at the start of the swing, in metres per second.
@export var step_impulse: float = 2.4


## Total time this step occupies if it is not cancelled or chained out of.
func total_duration() -> float:
	return windup + active + recovery
