const pos = array(vec2f(0.0, -1.0), vec2f(1.0, -1.0), vec2f(0.0, 0.0), vec2f(1.0, 0.0));

struct VertexInput {
    @builtin(vertex_index) vertex: u32,
    @builtin(instance_index) instance: u32,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texcoord: vec2f,
};

struct Char {
    tex_offset: vec2f,
    tex_extent: vec2f,
    size: vec2f,
    offset: vec2f,
};

struct FormattedText {
    transform: mat4x4f,
    fill_color: vec4f,
    outline_color: vec4f,
    scale: f32,
    px_range: f32,
    outline_width_px: f32,
    _padding: f32,
    chars: array<vec3f>,
};

struct Camera {
    projection: mat4x4f,
    view: mat4x4f,
};

@group(0) @binding(0) var font_texture: texture_2d<f32>;
@group(0) @binding(1) var font_sampler: sampler;
@group(0) @binding(2) var<storage> chars: array<Char>;

@group(1) @binding(0) var<uniform> camera: Camera;
@group(1) @binding(1) var<storage> text: FormattedText;

@vertex
fn vertexMain(input: VertexInput) -> VertexOutput {
    let text_element = text.chars[input.instance];
    let glyph = chars[u32(text_element.z)];
    let char_pos = (pos[input.vertex] * glyph.size + text_element.xy + glyph.offset) * text.scale;

    var output: VertexOutput;
    output.position = camera.projection * camera.view * text.transform * vec4f(char_pos, 0.0, 1.0);
    output.texcoord = pos[input.vertex] * vec2f(1.0, -1.0);
    output.texcoord *= glyph.tex_extent;
    output.texcoord += glyph.tex_offset;
    return output;
}

fn sampleMsdf(texcoord: vec2f) -> f32 {
    let c = textureSample(font_texture, font_sampler, texcoord);
    return max(min(c.r, c.g), min(max(c.r, c.g), c.b));
}

fn premultiply(color: vec4f) -> vec4f {
    return vec4f(color.rgb * color.a, color.a);
}

@fragment
fn fragmentMain(input: VertexOutput) -> @location(0) vec4f {
    let texture_size = vec2f(textureDimensions(font_texture, 0));
    let dx = texture_size.x * length(vec2f(dpdxFine(input.texcoord.x), dpdyFine(input.texcoord.x)));
    let dy = texture_size.y * length(vec2f(dpdxFine(input.texcoord.y), dpdyFine(input.texcoord.y)));
    let to_pixels = text.px_range * inverseSqrt(dx * dx + dy * dy);
    let sig_dist = sampleMsdf(input.texcoord) - 0.5;
    let px_dist = sig_dist * to_pixels;

    let edge_width = 0.5;
    let fill_alpha = smoothstep(-edge_width, edge_width, px_dist);
    let outline_alpha = smoothstep(-edge_width, edge_width, px_dist + text.outline_width_px);
    let outline_band = max(outline_alpha - fill_alpha, 0.0);

    let fill = premultiply(text.fill_color) * fill_alpha;
    let outline = premultiply(text.outline_color) * outline_band;
    let result = fill + outline;

    if (result.a < 0.001) {
        discard;
    }

    return result;
}
