extends KinematicBody2D

signal finished_kill

var steering_control = preload( "res://scripts/steering.gd" ).new()
var GRAB_PLAYER_TIME = 0.5
var grab_player_timer = GRAB_PLAYER_TIME

enum STATES { IDLE, ATTACK, GRABBING, KILL, DEAD }
var state_cur = -1
var state_nxt = STATES.IDLE

# direction
onready var rotate = get_node( "rotate" )
var dir_cur = 0
var dir_nxt = 1
var dir_timer = 0.2

# motion
var vel = Vector2()
var target_path = []
var neighbours = []

# external impulses
var external_impulse = Vector2()
var external_impulse_timer = 0


func _ready():
	steering_control.max_vel = 50
	steering_control.max_force = 500
	var anim_pos = rand_range( 0, 3 )
	get_node( "anim_body" ).seek( 0.8 * fmod( anim_pos, 1 ) )
	get_node( "anim_head" ).seek( 0.8 * anim_pos )
	set_fixed_process( true )




func _fixed_process(delta):
	var steering_force = Vector2()
	var flocking_force = Vector2()
	
	state_cur = state_nxt
	
	if state_cur == STATES.IDLE:
		# do nothing
		pass
	if state_cur == STATES.ATTACK:
		# steer towards player
		if ( game.player_char == game.PLAYER_CHAR.HUMAN or \
				game.player_char == game.PLAYER_CHAR.HUMAN_SWORD or \
				game.player_char == game.PLAYER_CHAR.HUMAN_GUN ) and \
				game.player != null and game.player.get_ref() != null and \
				( not game.player.get_ref().is_dead() ):
			steering_force = steering_control.steering_and_arriving( \
					get_global_pos(), game.player.get_ref().get_global_pos(), 
					vel, 10, delta )
		# flocking behavior
		flocking_force = steering_control.flocking( \
				self, neighbours, 10000, 1, 1 ) # 10000
		# dampening
		vel *= 0.98
	elif state_cur == STATES.DEAD:
		# dampening
		vel *= 0.95
		if vel.length_squared() < 4:
			vel = Vector2()
		# set death animation
		if get_node( "anim_head" ).get_current_animation() != "kill":
			get_node( "anim_body" ).stop()
			get_node( "anim_head" ).play( "kill" )
		if vel.length_squared() == 0:
			#print( "finished dying" )
			set_fixed_process( false )
			_change_to_item()
	elif state_cur == STATES.GRABBING:
		# steer towards player without flocking
		if game.player != null and game.player.get_ref() != null and \
				( not game.player.get_ref().is_dead() ):
			steering_force = steering_control.steering_and_arriving( \
					get_global_pos(), game.player.get_ref().get_global_pos(), 
					vel, 10, delta )
		# count grabbing time
		#print( get_name(), ": grabbing player, ", grab_player_timer )
		grab_player_timer -= delta
		if grab_player_timer <= 0:
			state_nxt = STATES.KILL
	elif state_cur == STATES.KILL:
		# kill player
		if game.player != null and game.player.get_ref() != null:
			if not game.player.get_ref().is_dead():
				#print( get_name(), ": killing player " )
				game.player.get_ref().die( self )
				# instance death scene
				var death = preload( "res://scenes/monster_1_kill_player.tscn" ).instance()
				death.get_node( "Sprite" ).set_global_pos( get_global_pos() )
				death.connect( "finished", self, "_on_finished_killing_player_scene" )
				get_parent().add_child( death )
				hide()
				set_fixed_process( false )
				vel = Vector2()
				steering_force = Vector2()
				flocking_force = Vector2()
				external_impulse = Vector2()
				state_nxt = STATES.IDLE
			else:
				#print( get_name(), ": was too late " )
				state_nxt = STATES.IDLE
		pass
	
	
	# apply all forces
	var force = steering_force + flocking_force
	force = steering_control.truncate( force, steering_control.max_force )
	vel += force * delta
	vel = steering_control.truncate( vel, steering_control.max_vel )
	
	# external forces
	vel += external_impulse * delta
	external_impulse_timer -= delta
	if external_impulse_timer <= 0:
		external_impulse = Vector2()
	
	
	
	# move
	vel = move_and_slide( vel )
	
	# direction
	if vel.x > 0:
		dir_nxt = 1
	elif vel.x < 0:
		dir_nxt = -1
	if dir_nxt != dir_cur:
		dir_timer -= delta
		if dir_timer <= 0:
			dir_timer = 0.2
			dir_cur = dir_nxt
			rotate.set_scale( Vector2( dir_cur, 1 ) )



func _on_flocking_area_area_enter( area ):
	var obj = area.get_parent()
	if obj.is_in_group( "monster" ):
		if game.findweak( obj, neighbours ) == -1:
			neighbours.append( weakref( obj ) )



func _on_flocking_area_area_exit( area ):
	var obj = area.get_parent()
	if obj.is_in_group( "monster" ):
		var pos = game.findweak( obj, neighbours )
		if pos != -1:
			neighbours.remove( pos )





#var caught_player = false
#var caught_player_timer = CATCH_PLAYER_TIME
func _on_hitbox_area_enter( area ):
	if is_dead(): return
	if state_cur != STATES.GRABBING:
		var obj = area.get_parent()
		if obj.is_in_group( "player" ):
			#print( get_name(), ": grabbing player " )
			state_nxt = STATES.GRABBING
			grab_player_timer = GRAB_PLAYER_TIME



func _on_hitbox_area_exit( area ):
	if is_dead(): return
	if state_cur == STATES.GRABBING:
		var obj = area.get_parent()
		if obj.is_in_group( "player" ):
			#print( get_name(), ": releasing player " )
			state_nxt = STATES.ATTACK
			grab_player_timer = GRAB_PLAYER_TIME


func _on_killplayertimer_timeout():
	return
	show()
	set_fixed_process( true )



#---------------------------------------
# function called when the monster is hit by the hittin source
#---------------------------------------
func get_hit( source ):
	if state_cur != STATES.DEAD and state_nxt != STATES.DEAD and \
			state_cur != STATES.GRABBING and state_nxt != STATES.GRABBING:
		# monster dies immediately
		state_nxt = STATES.DEAD
		return true
	return false

#---------------------------------------
# function called to apply external force
#---------------------------------------
func set_external_force( force, duration ):
	if state_cur != STATES.DEAD and state_nxt != STATES.DEAD and \
			state_cur != STATES.GRABBING and state_nxt != STATES.GRABBING:
		# create force
		external_impulse_timer = duration
		external_impulse = force
		# create blood splatter
		var blood = preload( "res://scenes/blood_particles.tscn" ).instance()
		blood.set_pos( get_pos() )
		blood.set_rot( external_impulse.angle() )
		get_parent().add_child( blood )

#---------------------------------------
# function called to let know if its dead
#---------------------------------------
func is_dead():
	if state_cur == STATES.DEAD:
		return true
	return false





func _on_finished_killing_player_scene():
	show()
	set_fixed_process( true )
	emit_signal( "finished_kill" )


func _change_to_item():
	# delete unecessary nodes
	get_node( "anim_body" ).queue_free()
	get_node( "anim_head" ).queue_free()
	get_node( "body" ).queue_free()
	get_node( "flocking_area/CollisionShape2D" ).queue_free()
	get_node( "flocking_area" ).queue_free()
	get_node( "hitbox/CollisionShape2D" ).queue_free()
	get_node( "hitbox" ).queue_free()
	get_node( "damagebox/CollisionShape2D" ).queue_free()
	get_node( "damagebox" ).queue_free()
	# change mask of kinematic body
	set_layer_mask_bit( 1, false )
	set_collision_mask_bit( 1, false )
	# change mask of item box
	get_node( "itemarea" ).set_layer_mask_bit( 2, true )
	get_node( "itemarea" ).set_collision_mask_bit( 2, true )