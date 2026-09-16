uniform FragInfo {
  vec4 tint;     // linear RGBA, multiplied into the sampled color
  // x: 0 premultiplied source-over, 1 additive. y: reciprocal soft depth
  // fade distance (0 disables). z: reciprocal camera near fade distance
  // (0 disables). w: 1 opaque alpha-tested (discard alpha < 0.5, no blending).
  vec4 params;
  // xy: reciprocal viewport size, for the gl_FragCoord screen UV. zw:
  // unused.
  vec4 viewport;
}
frag_info;

uniform sampler2D base_color_texture;
// The opaque linear (planar view-space) depth in world units, bound to a
// white placeholder when the depth prepass did not run (the fade is
// disabled then, so it is never sampled meaningfully).
uniform sampler2D scene_depth;

// Stage inputs. The standard engine varyings come first, in the exact order
// material_varyings.glsl declares them, so a billboard vertex shader that
// also serves the depth-prepass/selection-mask passes assigns matching
// interpolant locations. The sprite-specific varyings follow in the billboard
// vertex shader's order.
in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector;
in vec2 v_texture_coords;
in vec4 v_color;
in vec2 v_uv;
in vec2 v_uv2;
in float v_frame_blend;
in float v_view_depth;

out vec4 frag_color;

// Distance fog (the FogInfo block + ApplyFog). Declared after the varyings it
// reads (v_position, v_viewvector).
#include <fog.glsl>

const float kGamma = 2.2;
vec3 SRGBToLinear(vec3 color) { return pow(color, vec3(kGamma)); }

void main() {
  // Crossfade between adjacent flipbook cells (v_frame_blend is zero when
  // the geometry has blending off, collapsing to a single sample's value).
  vec4 base = mix(
      texture(base_color_texture, v_uv),
      texture(base_color_texture, v_uv2),
      v_frame_blend);
  // Linearize the sRGB-encoded texture; the resolve pass applies display
  // encoding. The scene-color target stores linear HDR premultiplied alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * v_color.rgb * frag_info.tint.rgb;
  float alpha = base.a * v_color.a * frag_info.tint.a;

  // Soft particles: fade out as the sprite approaches the opaque geometry
  // behind it, so intersections dissolve instead of cutting a hard edge.
  float soft_inv = frag_info.params.y;
  if (soft_inv > 0.0) {
    vec2 screen_uv = clamp(gl_FragCoord.xy * frag_info.viewport.xy,
                           vec2(0.001), vec2(0.999));
    float scene_d = texture(scene_depth, screen_uv).r;
    alpha *= clamp((scene_d - v_view_depth) * soft_inv, 0.0, 1.0);
  }
  // Camera near fade: dissolve sprites before the camera clips through them.
  float near_inv = frag_info.params.z;
  if (near_inv > 0.0) {
    alpha *= clamp(v_view_depth * near_inv - 0.35, 0.0, 1.0);
  }

  // Opaque alpha-tested sprites discard transparent pixels and write fully
  // opaque fragments (no premultiply, no blending) so the depth buffer
  // resolves their ordering against every other draw.
  if (frag_info.params.w > 0.5) {
    if (alpha < 0.5) discard;
    frag_color = ApplyFog(vec4(rgb, 1.0), fog.color.rgb);
    return;
  }

  // The color encoder's translucent pass blends with premultiplied
  // source-over: out = src.rgb + (1 - src.a) * dst. Premultiplying the color
  // by alpha gives normal blending; forcing the output alpha to zero (while
  // keeping the premultiplied color) turns the same pass additive, so both
  // modes share one pipeline.
  float out_alpha = mix(alpha, 0.0, frag_info.params.x);
  // Sprites have no environment bound, so pass the flat fog color as the sky
  // color; the sky-color mix in ApplyFog is then inert.
  frag_color = ApplyFog(vec4(rgb * alpha, out_alpha), fog.color.rgb);
}
