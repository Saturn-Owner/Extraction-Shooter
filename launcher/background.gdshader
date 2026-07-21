// Hintergrund des Launchers — Modernist / "Red Snow": heller Schnee-Grund,
// ruhig, aber lebendig.
//
// Drei Schichten, alle prozedural (kein Bild-Asset):
//   1. Schnee-Nebel: langsam ziehendes Wertrauschen, verdunkelt den weissen
//      Grund nur einen Hauch (grauer Schneezug statt Aufhellen)
//   2. Warnstreifen: feine rote Diagonalen am unteren Rand
//   3. Roter Schein von unten Mitte + dezente Vignette zu den Ecken
//
// Alle Staerken sind uniforms — Stellschrauben fuers gemeinsame Zaubern.
shader_type canvas_item;

// Schnee-Weiss (#f3f2f2) als Grund, Signal-Rot (#ec3013) als einziger Akzent.
uniform vec4 base_color : source_color = vec4(0.953, 0.949, 0.949, 1.0);
uniform vec4 glow_color : source_color = vec4(0.925, 0.188, 0.075, 1.0);
uniform float fog_strength : hint_range(0.0, 0.3) = 0.06;
uniform float fog_speed : hint_range(0.0, 0.2) = 0.015;
uniform float stripe_strength : hint_range(0.0, 0.5) = 0.10;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;

// Einfaches Wertrauschen mit weicher Überblendung.
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Mehrere Rauschoktaven übereinander ergeben den Nebel.
float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.1;
		amplitude *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 uv = UV;
	vec3 color = base_color.rgb;

	// 1. Schnee-Nebel — zieht ganz langsam nach rechts oben und verdunkelt
	//    den weissen Grund minimal (auf hellem Grund heisst "lebendig": abdunkeln).
	vec2 drift = vec2(TIME * fog_speed, TIME * fog_speed * -0.4);
	float fog = fbm(uv * 3.0 + drift);
	color -= (fog - 0.5) * fog_strength;

	// 2. Warnstreifen unten: rote Diagonalen, die zum Rand hin auftauchen.
	float band = smoothstep(0.86, 1.0, uv.y);
	float diagonal = step(0.5, fract((uv.x * 8.0 + uv.y * 8.0)));
	color = mix(color, glow_color.rgb, diagonal * band * stripe_strength);

	// 3. Roter Schein von unten Mitte + Vignette zu den Ecken.
	float glow = 1.0 - distance(uv, vec2(0.5, 1.05));
	color = mix(color, glow_color.rgb, max(glow, 0.0) * max(glow, 0.0) * glow_strength);
	float vignette = distance(uv, vec2(0.5, 0.45));
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(color, 1.0);
}
