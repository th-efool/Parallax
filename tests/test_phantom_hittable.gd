extends Node

func run():
	var phantom = PhantomTwin.new()
	phantom.realm_affinity = RealmReactive.Affinity.MIRROR_ONLY
	add_child(phantom)
	
	# Assume we are in Reality
	# How do I simulate RealmManager?
	# This might be too complicated for a simple test.
	print("Phantom hittable in Reality: ", phantom.is_hittable_now())
	
	phantom.queue_free()
	get_tree().quit()
