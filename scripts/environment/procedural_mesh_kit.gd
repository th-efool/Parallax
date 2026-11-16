class_name ProcMeshKit
extends RefCounted
## Static procedural-geometry kit for the Grand Journey level. Every generator emits triangles through
## `_tri()`, which enforces Godot's clockwise front-face winding from an intended outward normal, so
## the meshes light and cull correctly regardless of how the outline was authored.
## All meshes are UV-light: the level's `realm_pbr.gdshader` is world-space triplanar.


class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, smooth_normals: Array = []) -> void:
		# Godot front faces are clockwise -> cross(b - a, c - a) must point AGAINST the outward normal.
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t: Vector3 = b
			b = c
			c = t
			if smooth_normals.size() == 3:
				var tn: Vector3 = smooth_normals[1]
				smooth_normals[1] = smooth_normals[2]
				smooth_normals[2] = tn
		verts.append_array(PackedVector3Array([a, b, c]))
		if smooth_normals.size() == 3:
			normals.append_array(PackedVector3Array([smooth_normals[0], smooth_normals[1], smooth_normals[2]]))
		else:
			normals.append_array(PackedVector3Array([n, n, n]))
		uvs.append_array(PackedVector2Array([Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y)]))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		tri(a, b, c, n)
		tri(a, c, d, n)

	func box(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
		var h: Vector3 = size * 0.5
		var faces: Array = [
			[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
			[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
			[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		]
		for f in faces:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var fc: Vector3 = n * h
			var ue: Vector3 = u * h
			var ve: Vector3 = v * h
			var p0: Vector3 = center + basis * (fc - ue - ve)
			var p1: Vector3 = center + basis * (fc + ue - ve)
			var p2: Vector3 = center + basis * (fc + ue + ve)
			var p3: Vector3 = center + basis * (fc - ue + ve)
			quad(p0, p1, p2, p3, (basis * n).normalized())

	func commit(mesh: ArrayMesh = null) -> ArrayMesh:
		var m: ArrayMesh = mesh if mesh != null else ArrayMesh.new()
		if verts.is_empty():
			return m
		# Always emit an index buffer: SurfaceTool.append_from() (used by static batching) silently drops
		# non-indexed geometry when it is merged with indexed meshes such as BoxMesh/CylinderMesh.
		var idx := PackedInt32Array()
		idx.resize(verts.size())
		for i in range(verts.size()):
			idx[i] = i
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


# ------------------------------------------------------------------------------------------------
# Extrusions & architecture
# ------------------------------------------------------------------------------------------------

static func extrude_polygon(outline: PackedVector2Array, depth: float, b: Builder = null, offset: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	## Extrudes a simple (possibly concave) polygon drawn in the XY plane along Z (centred on z = 0).
	var own: bool = b == null
	if own:
		b = Builder.new()
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	var hz: float = depth * 0.5
	var nf: Vector3 = (offset.basis * Vector3(0, 0, 1)).normalized()
	for i in range(0, tris.size(), 3):
		var a2: Vector2 = outline[tris[i]]
		var b2: Vector2 = outline[tris[i + 1]]
		var c2: Vector2 = outline[tris[i + 2]]
		b.tri(offset * Vector3(a2.x, a2.y, hz), offset * Vector3(b2.x, b2.y, hz), offset * Vector3(c2.x, c2.y, hz), nf)
		b.tri(offset * Vector3(a2.x, a2.y, -hz), offset * Vector3(b2.x, b2.y, -hz), offset * Vector3(c2.x, c2.y, -hz), -nf)
	# Side walls: outward normal = perpendicular of the edge pointing away from the polygon interior.
	var area: float = 0.0
	for i in range(outline.size()):
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % outline.size()]
		area += p.x * q.y - q.x * p.y
	var ccw: bool = area > 0.0
	for i in range(outline.size()):
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % outline.size()]
		var e: Vector2 = q - p
		if e.length_squared() < 1e-8:
			continue
		var out2: Vector2 = Vector2(e.y, -e.x).normalized() if ccw else Vector2(-e.y, e.x).normalized()
		var n3: Vector3 = (offset.basis * Vector3(out2.x, out2.y, 0.0)).normalized()
		b.quad(offset * Vector3(p.x, p.y, hz), offset * Vector3(q.x, q.y, hz), offset * Vector3(q.x, q.y, -hz), offset * Vector3(p.x, p.y, -hz), n3)
	return b.commit() if own else null


static func arch_outline(width: float, height: float, opening_w: float, spring_h: float, segments: int = 14) -> PackedVector2Array:
	## Inverted-U wall slab with a round-headed opening. Origin at bottom centre.
	var w: float = width * 0.5
	var o: float = opening_w * 0.5
	var pts := PackedVector2Array([Vector2(-w, 0.0), Vector2(-o, 0.0), Vector2(-o, spring_h)])
	for i in range(1, segments):
		var t: float = PI - PI * float(i) / float(segments)
		pts.append(Vector2(cos(t) * o, spring_h + sin(t) * o))
	pts.append_array(PackedVector2Array([Vector2(o, spring_h), Vector2(o, 0.0), Vector2(w, 0.0), Vector2(w, height), Vector2(-w, height)]))
	return pts


static func arch_mesh(width: float, height: float, opening_w: float, spring_h: float, depth: float) -> ArrayMesh:
	return extrude_polygon(arch_outline(width, height, opening_w, spring_h), depth)


static func steps_mesh(width: float, rise_total: float, run_total: float, count: int) -> ArrayMesh:
	## Solid staircase climbing along +Z from (0,0,0) to (0, rise_total, run_total). Each step is a box
	## from the ground up to its tread height, so the side silhouette reads as a proper stepped flank.
	var b := Builder.new()
	var rise: float = rise_total / float(count)
	var run: float = run_total / float(count)
	for i in range(count):
		var top: float = rise * float(i + 1)
		var z0: float = run * float(i)
		b.box(Vector3(0.0, top * 0.5, z0 + run * 0.5), Vector3(width, top, run))
	return b.commit()


static func ring_sector_mesh(r_in: float, r_out: float, y_bottom: float, y_top: float, a0: float, a1: float, segments: int, b: Builder = null) -> ArrayMesh:
	## Annular sector slab (seating tiers, podium walls). Angles in radians around +Y, 0 = +Z.
	var own: bool = b == null
	if own:
		b = Builder.new()
	for i in range(segments):
		var t0: float = lerpf(a0, a1, float(i) / float(segments))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(segments))
		var d0 := Vector3(sin(t0), 0.0, cos(t0))
		var d1 := Vector3(sin(t1), 0.0, cos(t1))
		var yb := Vector3(0, y_bottom, 0)
		var yt := Vector3(0, y_top, 0)
		# top
		b.quad(d0 * r_in + yt, d1 * r_in + yt, d1 * r_out + yt, d0 * r_out + yt, Vector3.UP)
		# outer
		var no: Vector3 = ((d0 + d1) * 0.5).normalized()
		b.quad(d0 * r_out + yb, d1 * r_out + yb, d1 * r_out + yt, d0 * r_out + yt, no)
		# inner
		b.quad(d0 * r_in + yb, d0 * r_in + yt, d1 * r_in + yt, d1 * r_in + yb, -no)
	return b.commit() if own else null


static func cavea_mesh(r_start: float, tier_depth: float, tier_rise: float, tiers: int, y0: float, a0: float, a1: float, segments: int) -> ArrayMesh:
	## Stepped amphitheatre seating: `tiers` concentric ring steps rising outward.
	var b := Builder.new()
	for t in range(tiers):
		var r_in: float = r_start + tier_depth * float(t)
		ring_sector_mesh(r_in, r_in + tier_depth, y0, y0 + tier_rise * float(t + 1), a0, a1, segments, b)
	return b.commit()


static func column_mesh(radius: float, height: float, flutes: int = 16) -> ArrayMesh:
	## Classical column: square plinth, torus-ish base ring, fluted tapering shaft, echinus + abacus capital.
	var b := Builder.new()
	var base_h: float = radius * 0.6
	b.box(Vector3(0, base_h * 0.5, 0), Vector3(radius * 2.6, base_h, radius * 2.6))
	b.box(Vector3(0, base_h + radius * 0.15, 0), Vector3(radius * 2.25, radius * 0.3, radius * 2.25))
	var shaft_y0: float = base_h + radius * 0.3
	var cap_h: float = radius * 0.9
	var shaft_y1: float = height - cap_h
	var segs: int = flutes * 2
	for i in range(segs):
		var t0: float = TAU * float(i) / float(segs)
		var t1: float = TAU * float(i + 1) / float(segs)
		var r0: float = radius * (0.93 if i % 2 == 0 else 1.0)
		var r1: float = radius * (0.93 if (i + 1) % 2 == 0 else 1.0)
		var top_k: float = 0.86
		var a := Vector3(sin(t0) * r0, shaft_y0, cos(t0) * r0)
		var bb := Vector3(sin(t1) * r1, shaft_y0, cos(t1) * r1)
		var c := Vector3(sin(t1) * r1 * top_k, shaft_y1, cos(t1) * r1 * top_k)
		var d := Vector3(sin(t0) * r0 * top_k, shaft_y1, cos(t0) * r0 * top_k)
		var nn := Vector3(sin((t0 + t1) * 0.5), 0.08, cos((t0 + t1) * 0.5)).normalized()
		b.quad(a, bb, c, d, nn)
	# Echinus (flared ring) and abacus
	var er: float = radius * 0.86
	for i in range(segs):
		var t0: float = TAU * float(i) / float(segs)
		var t1: float = TAU * float(i + 1) / float(segs)
		var d0 := Vector3(sin(t0), 0, cos(t0))
		var d1 := Vector3(sin(t1), 0, cos(t1))
		var y0: float = shaft_y1
		var y1: float = shaft_y1 + cap_h * 0.45
		var nn := ((d0 + d1) * 0.5).normalized() + Vector3(0, 0.6, 0)
		b.quad(d0 * er + Vector3(0, y0, 0), d1 * er + Vector3(0, y0, 0), d1 * radius * 1.35 + Vector3(0, y1, 0), d0 * radius * 1.35 + Vector3(0, y1, 0), nn.normalized())
	b.box(Vector3(0, height - cap_h * 0.275, 0), Vector3(radius * 2.9, cap_h * 0.55, radius * 2.9))
	return b.commit()


static func portcullis_mesh(width: float, height: float, bar: float = 0.12, spacing: float = 0.45) -> ArrayMesh:
	var b := Builder.new()
	var nx: int = maxi(2, int(width / spacing))
	for i in range(nx + 1):
		var x: float = -width * 0.5 + width * float(i) / float(nx)
		b.box(Vector3(x, height * 0.5, 0), Vector3(bar, height, bar))
		# spike tips
		b.box(Vector3(x, 0.05, 0), Vector3(bar * 0.6, 0.1, bar * 0.6))
	var ny: int = maxi(2, int(height / (spacing * 1.6)))
	for j in range(ny + 1):
		var y: float = height * float(j) / float(ny)
		b.box(Vector3(0, clampf(y, bar, height - bar * 0.5), 0), Vector3(width, bar * 1.2, bar * 0.7))
	return b.commit()


static func gear_mesh(radius: float, thickness: float, teeth: int, hub_r: float) -> ArrayMesh:
	## Spoked cog in the XY plane (rotate about Z). Teeth + rim + 6 spokes + hub.
	var b := Builder.new()
	var outline := PackedVector2Array()
	var tooth_h: float = radius * 0.12
	for i in range(teeth * 4):
		var a: float = TAU * float(i) / float(teeth * 4)
		var r: float = radius + (tooth_h if (i % 4 == 1 or i % 4 == 2) else 0.0)
		outline.append(Vector2(cos(a) * r, sin(a) * r))
	var inner := PackedVector2Array()
	var rim_in: float = radius * 0.8
	for i in range(teeth * 4):
		var a: float = TAU * float(i) / float(teeth * 4)
		inner.append(Vector2(cos(a) * rim_in, sin(a) * rim_in))
	# Rim as a ring: build quads between outline and inner on both faces + outer/inner walls.
	var hz: float = thickness * 0.5
	for i in range(outline.size()):
		var j: int = (i + 1) % outline.size()
		var o0 := Vector3(outline[i].x, outline[i].y, 0)
		var o1 := Vector3(outline[j].x, outline[j].y, 0)
		var i0 := Vector3(inner[i].x, inner[i].y, 0)
		var i1 := Vector3(inner[j].x, inner[j].y, 0)
		var f := Vector3(0, 0, hz)
		b.quad(o0 + f, o1 + f, i1 + f, i0 + f, Vector3(0, 0, 1))
		b.quad(o0 - f, o1 - f, i1 - f, i0 - f, Vector3(0, 0, -1))
		var no := Vector3((o0 + o1).x, (o0 + o1).y, 0).normalized()
		b.quad(o0 - f, o1 - f, o1 + f, o0 + f, no)
		b.quad(i0 - f, i1 - f, i1 + f, i0 + f, -no)
	for s in range(6):
		var a: float = TAU * float(s) / 6.0
		var mid: float = (hub_r + rim_in) * 0.5
		b.box(Vector3(cos(a) * mid, sin(a) * mid, 0), Vector3(rim_in - hub_r + 0.1, radius * 0.12, thickness * 0.8), Basis(Vector3(0, 0, 1), a))
	b.box(Vector3.ZERO, Vector3(hub_r * 2.0, hub_r * 2.0, thickness * 1.3))
	return b.commit()


# ------------------------------------------------------------------------------------------------
# Organic rock / terrain
# ------------------------------------------------------------------------------------------------

static func rock_mesh(size: Vector3, seed_val: int, roughness: float = 0.22, subdiv: int = 10, boxy: float = 0.0, taper: float = 0.0) -> ArrayMesh:
	## Noise-displaced blob (boxy = 0) or cliff block (boxy = 1). Smooth normals, seam-free (UV-less indexing).
	var src: Array
	if boxy > 0.5:
		var bm := BoxMesh.new()
		bm.size = Vector3(2, 2, 2)
		bm.subdivide_width = subdiv
		bm.subdivide_height = subdiv
		bm.subdivide_depth = subdiv
		src = bm.get_mesh_arrays()
	else:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = subdiv * 2
		sm.rings = subdiv
		src = sm.get_mesh_arrays()
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.9
	var pts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var displaced := PackedVector3Array()
	displaced.resize(pts.size())
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var dir: Vector3 = p.normalized() if p.length_squared() > 1e-6 else Vector3.UP
		var n1: float = noise.get_noise_3dv(p * 1.3)
		var n2: float = noise.get_noise_3dv(p * 4.1 + Vector3(9, 3, 1)) * 0.35
		# Horizontal strata for cliff blocks
		var strata: float = sin(p.y * 7.0 + n1 * 2.0) * 0.06 * boxy
		var q: Vector3 = p + dir * ((n1 + n2) * roughness + strata)
		# Optional taper narrows the mass toward the top (spires), with a noisy, uneven crown.
		var k: float = 1.0 - taper * clampf((p.y + 1.0) * 0.5, 0.0, 1.0)
		q.x *= k
		q.z *= k
		if taper > 0.0 and p.y > 0.6:
			q.y += n1 * taper * 0.6
		displaced[i] = q * size * 0.5
	for i in range(0, idx.size(), 3):
		# Re-emit without UVs so SurfaceTool.index() welds seams; winding of source primitives is preserved.
		st.add_vertex(displaced[idx[i]])
		st.add_vertex(displaced[idx[i + 1]])
		st.add_vertex(displaced[idx[i + 2]])
	st.index()
	st.generate_normals()
	return st.commit()


static func mountain_mesh(radius: float, height: float, seed_val: int) -> ArrayMesh:
	## Distant massif for the horizon: a heightfield disc with ridged multi-peak noise (not a cone), so the
	## silhouette reads as a jagged range with shoulders, couloirs and secondary summits.
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	noise.frequency = 1.1
	var base_n := FastNoiseLite.new()
	base_n.seed = seed_val + 31
	base_n.frequency = 0.9
	var rings: int = 18
	var segs: int = 56
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in range(rings + 1):
		var t: float = float(r) / float(rings)          # 0 = outer foot, 1 = centre
		var row := PackedVector3Array()
		for s in range(segs):
			var a: float = TAU * float(s) / float(segs)
			var dir := Vector3(sin(a), 0, cos(a))
			var rr: float = radius * (1.0 - t)
			var p2 := Vector2(dir.x, dir.z) * (1.0 - t) * 1.6
			var ridge: float = (noise.get_noise_2dv(p2) + 1.0) * 0.5
			var mass: float = smoothstep(0.0, 1.0, t) * (0.75 + 0.5 * (base_n.get_noise_2dv(p2 * 0.6) + 1.0) * 0.5)
			var yy: float = height * mass * (0.45 + 0.75 * ridge * ridge)
			row.append(dir * rr + Vector3(0, yy, 0))
		grid.append(row)
	for r in range(rings):
		var row0: PackedVector3Array = grid[r]
		var row1: PackedVector3Array = grid[r + 1]
		for s in range(segs):
			var s1: int = (s + 1) % segs
			var a: Vector3 = row0[s]
			var bb: Vector3 = row0[s1]
			var c: Vector3 = row1[s1]
			var d: Vector3 = row1[s]
			var out: Vector3 = Vector3(a.x + bb.x, 0, a.z + bb.z).normalized() + Vector3(0, 0.5, 0)
			_st_tri(st, a, bb, c, out)
			_st_tri(st, a, c, d, out)
	st.index()
	st.generate_normals()
	return st.commit()


static func sword_blade_outline(width: float, length: float) -> PackedVector2Array:
	## Blade seen face-on, point DOWN at y = 0 (plunged into the ground), ricasso at the top.
	var w: float = width * 0.5
	return PackedVector2Array([
		Vector2(0.0, -length * 0.08), Vector2(w * 0.78, length * 0.12), Vector2(w * 0.95, length * 0.86),
		Vector2(w, length), Vector2(-w, length), Vector2(-w * 0.95, length * 0.86), Vector2(-w * 0.78, length * 0.12),
	])


static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
